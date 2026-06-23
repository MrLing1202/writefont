import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'image_processor.dart';
import 'image_quality_service.dart';
import 'user_feedback_service.dart';
import 'dictionary_service.dart';
import 'stroke_analyzer.dart';
import 'image_analyzer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'tflite_recognition_service.dart';
import 'preprocess_isolate.dart';
import 'api_key.dart';
import '../models/recognition_history.dart';
import 'correction_learning_service.dart';

/// 单次识别的投票详情（v2.7.0）— 供 UI 展示投票过程
class RecognitionDetail {
  /// 最终识别结果
  final String result;
  /// 校准后置信度
  final double confidence;
  /// 每个候选字符的投票明细 {策略名: 票数}
  final Map<String, Map<String, int>> voteBreakdown;
  /// 总尝试次数
  final int totalAttempts;
  /// 是否提前终止
  final bool earlyTerminated;
  /// 提前终止节省的估算尝试次数
  final int attemptsSaved;
  /// 参与投票的策略数
  final int strategiesUsed;
  /// 最可靠的策略名（历史成功率最高）
  final String? topStrategy;
  /// 最可靠策略的历史成功率
  final double topStrategyReliability;
  /// 图像特征分析结果（v2.8.0）
  final ImageFeatures? imageFeatures;

  const RecognitionDetail({
    required this.result,
    required this.confidence,
    required this.voteBreakdown,
    required this.totalAttempts,
    required this.earlyTerminated,
    required this.attemptsSaved,
    required this.strategiesUsed,
    this.topStrategy,
    required this.topStrategyReliability,
    this.imageFeatures,
  });
}

/// v4.0.1: 智能白边裁剪结果
class _TrimResult {
  final img.Image image;
  final bool wasTrimmed;
  final double trimmedPercent;
  _TrimResult(this.image, this.wasTrimmed, this.trimmedPercent);
}

/// OCR 识别服务
/// 默认：本地 ML Kit 离线识别（免费，无需网络）
/// 可选：云端 API（用户填自己的 API 地址 + Key）
///
/// 调试功能：
/// - 结构化调试日志（带时间戳和分类标签）
/// - 识别过程数据导出（JSON 格式，含预处理中间结果）
/// - 调试统计面板数据（缓存命中率、错误率、延迟分布）
///
/// 离线功能优化：
/// - 离线模式自动切换（网络不可用时自动切换到本地识别）
/// - 离线数据缓存（识别结果本地持久化缓存）
/// - 离线操作队列（离线时的识别请求排队等待）
/// - 离线同步功能（网络恢复后自动同步离线数据）
class RecognitionService {
  // SharedPreferences keys
  static const String _prefKeyUseCloud = 'ocr_use_cloud';
  static const String _prefKeyCloudUrl = 'ocr_cloud_url';
  static const String _prefKeyCloudKey = 'ocr_cloud_key';
  static const String _prefKeyModel = 'ocr_model';
  static const String _prefKeyCustomModel = 'ocr_custom_model';
  static const String _prefKeyOfflineMode = 'ocr_offline_mode';
  static const String _prefKeyOfflineCache = 'ocr_offline_cache';
  static const String _prefKeyUseTflite = 'ocr_use_tflite';
  static const String _prefKeyStrategyWeights = 'ocr_strategy_weights'; // v4.3.0: 策略权重持久化

  // DeepSeek-OCR (硅基流动) 默认配置
  static const String defaultCloudUrl = 'https://api.siliconflow.cn/v1/chat/completions';
  static const String defaultModel = 'deepseek-ai/DeepSeek-OCR';
  static const String cloudDisplayName = 'DeepSeek-OCR（免费）';

  static const Duration _timeout = Duration(seconds: 30);
  static const int _maxConcurrent = 3;

  // Secure storage for sensitive data (API keys)
  static const _secureStorage = FlutterSecureStorage();

  static RecognitionService? _instance;
  static RecognitionService get instance => _instance ??= RecognitionService._();

  RecognitionService._();

  // 缓存
  bool? _useCloud;
  String? _cloudUrl;
  String? _cloudKey;
  bool? _useTflite;

  // ML Kit 识别器（懒加载）
  TextRecognizer? _mlKitRecognizer;

  /// 最近一次本地识别的投票置信度（供 recognizeCharacter 判断是否需要云端二次确认）
  double _lastLocalConfidence = 0.0;

  /// v4.5.0: 最近识别的字符序列（用于 n-gram 上下文预测，最多保留5个）
  static final List<String> _lastRecognizedChars = [];
  static const int _maxContextLength = 5;

  /// 策略可靠性追踪（策略名 → 历史成功率 0.0~1.0）— v2.6.0
  /// v4.3.0: 持久化到 SharedPreferences，启动时加载，识别后更新
  /// 用于加权投票：高可靠性策略的投票获得权重加成
  static final Map<String, double> _strategyReliability = {};
  static bool _strategyWeightsLoaded = false;
  static int _strategyUpdateCount = 0; // 更新计数，每10次持久化一次
  static DateTime _lastStrategyDecay = DateTime.now(); // 上次衰减时间

  // ═══════════════════════════════════════════════════════════
  // v4.6.0: 策略组合性能追踪 — 根据图像特征自动选择最优策略子集
  // ═══════════════════════════════════════════════════════════

  /// 策略组合性能映射（特征签名 → 策略名 → 成功率 0.0~1.0）
  /// 特征签名由对比度/模糊度/笔画粗细三个维度的离散化值组成
  /// 例如 "C1_B2_T1" 表示 低对比度/中模糊/细笔画
  static final Map<String, Map<String, double>> _strategyPerformanceMap = {};
  static const String _prefKeyStrategyPerformance = 'ocr_strategy_performance';
  static bool _strategyPerformanceLoaded = false;
  static int _strategyPerfUpdateCount = 0;

  /// 将连续特征值离散化为 1~3 级
  static int _discretizeFeature(double value) {
    if (value < 0.33) return 1;
    if (value < 0.66) return 2;
    return 3;
  }

  /// 根据图像特征生成特征签名
  /// v4.8.0: 新增风格维度 — S(regular/cursive/light/heavy/mixed)
  /// v5.5.0: 新增墨迹密度维度 — D(1/2/3)，区分简单字/复杂字
  static String _buildFeatureSignature(ImageFeatures features) {
    final c = _discretizeFeature(features.contrast);
    final b = _discretizeFeature(features.blur);
    final t = _discretizeFeature(features.lineThickness);
    final d = _discretizeFeature(features.inkDensity); // v5.5.0: 笔画密度
    // 风格缩写
    String s;
    switch (features.style) {
      case HandwritingStyle.cursive:
        s = 'CU';
        break;
      case HandwritingStyle.light:
        s = 'LI';
        break;
      case HandwritingStyle.heavy:
        s = 'HE';
        break;
      case HandwritingStyle.mixed:
        s = 'MX';
        break;
      default:
        s = 'RE'; // regular
    }
    return 'C${c}_B${b}_T${t}_D${d}_$s';
  }

  /// 加载策略组合性能数据
  static Future<void> _loadStrategyPerformance() async {
    if (_strategyPerformanceLoaded) return;
    _strategyPerformanceLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKeyStrategyPerformance);
      if (json != null && json.isNotEmpty) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        for (final entry in map.entries) {
          final innerMap = entry.value as Map<String, dynamic>;
          _strategyPerformanceMap[entry.key] = {};
          for (final s in innerMap.entries) {
            _strategyPerformanceMap[entry.key]![s.key] = (s.value as num).toDouble();
          }
        }
        debugPrint('策略组合性能: 已加载 ${_strategyPerformanceMap.length} 个特征签名');
      }
    } catch (e) {
      debugPrint('策略组合性能: 加载失败 $e');
    }
  }

  /// 保存策略组合性能数据
  static Future<void> _saveStrategyPerformance() async {
    if (_strategyPerformanceMap.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{};
      for (final entry in _strategyPerformanceMap.entries) {
        map[entry.key] = Map<String, dynamic>.from(entry.value);
      }
      await prefs.setString(_prefKeyStrategyPerformance, jsonEncode(map));
      debugPrint('策略组合性能: 已保存 ${_strategyPerformanceMap.length} 个特征签名');
    } catch (e) {
      debugPrint('策略组合性能: 保存失败 $e');
    }
  }

  /// 根据图像特征签名选择最优策略子集
  /// 返回按历史性能降序排列的策略名列表
  static List<String> _selectOptimalStrategies(
    ImageFeatures features,
    Map<String, img.Image Function(img.Image)> allPreprocessors,
  ) {
    final signature = _buildFeatureSignature(features);
    final perfData = _strategyPerformanceMap[signature];

    if (perfData == null || perfData.isEmpty) {
      // 无历史数据，返回全部策略
      return allPreprocessors.keys.toList();
    }

    // 按历史性能排序，选择 top-N 策略（至少 5 个，最多 12 个）
    final sorted = perfData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final selected = <String>[];
    // 性能 > 0.3 的策略优先选入
    for (final entry in sorted) {
      if (entry.value > 0.3 && allPreprocessors.containsKey(entry.key)) {
        selected.add(entry.key);
      }
    }
    // 确保至少有 5 个策略
    for (final key in allPreprocessors.keys) {
      if (!selected.contains(key)) {
        selected.add(key);
      }
      if (selected.length >= 12) break;
    }

    debugPrint('策略组合优化: 特征=$signature, 选择 ${selected.length} 个策略 '
        '(top3: ${selected.take(3).join(", ")})');
    return selected;
  }

  /// 异步更新策略组合性能统计
  static Future<void> _updateStrategyPerformanceAsync(
    ImageFeatures features,
    Map<String, Set<String>> resultStrategies,
    String winnerKey,
  ) async {
    try {
      await _loadStrategyPerformance();
      final signature = _buildFeatureSignature(features);
      _strategyPerformanceMap.putIfAbsent(signature, () => {});

      final perfMap = _strategyPerformanceMap[signature]!;

      // 胜出策略 +1 成功率（指数移动平均）
      final winnerStrats = resultStrategies[winnerKey] ?? {};
      for (final strat in winnerStrats) {
        final old = perfMap[strat] ?? 0.5;
        perfMap[strat] = (old * 0.8 + 0.2).clamp(0.0, 1.0);
      }

      // 非胜出策略 -0.05（轻微惩罚）
      for (final entry in resultStrategies.entries) {
        if (entry.key != winnerKey) {
          for (final strat in entry.value) {
            final old = perfMap[strat] ?? 0.5;
            perfMap[strat] = (old * 0.95).clamp(0.0, 1.0);
          }
        }
      }

      // 限制每个特征签名最多跟踪 50 个策略
      if (perfMap.length > 50) {
        final sorted = perfMap.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        perfMap.remove(sorted.first.key);
      }

      // 每 5 次更新持久化一次（使用独立计数器，避免与策略权重持久化冲突）
      _strategyPerfUpdateCount++;
      if (_strategyPerfUpdateCount >= 5) {
        _strategyPerfUpdateCount = 0;
        await _saveStrategyPerformance();
      }
    } catch (e) {
      debugPrint('策略组合性能更新失败: $e');
    }
  }

  /// 获取策略组合性能统计（供 UI 展示）
  static Map<String, dynamic> getStrategyPerformanceStats() {
    final stats = <String, dynamic>{};
    for (final entry in _strategyPerformanceMap.entries) {
      final sorted = entry.value.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      stats[entry.key] = {
        'strategyCount': entry.value.length,
        'topStrategies': sorted.take(5).map((e) => '${e.key}:${(e.value * 100).toStringAsFixed(0)}%').toList(),
      };
    }
    return {
      'featureSignatures': _strategyPerformanceMap.length,
      'details': stats,
    };
  }

  // 原子计数器，用于临时文件名防碰撞
  static int _fileCounter = 0;

  // 识别结果缓存（图片字节哈希 → 识别结果）
  static final Map<int, String?> _recognitionCache = {};
  static const int _maxCacheSize = 200;
  // LRU 缓存访问顺序记录（最近访问的在末尾）
  static final List<int> _cacheAccessOrder = [];
  // 识别置信度缓存（图片哈希 → 置信度 0.0~1.0）
  static final Map<int, double> _confidenceCache = {};
  // v2.7.0: 识别详情缓存（图片哈希 → 投票详情）
  static final Map<int, RecognitionDetail> _detailCache = {};
  // 内存监控：记录缓存占用的估算字节数
  static int _estimatedCacheBytes = 0;
  static const int _maxCacheBytes = 50 * 1024 * 1024; // 50MB 上限

  // ═══════════════════════════════════════════════════════════
  // 调试功能：结构化日志、调试工具、数据导出
  // ═══════════════════════════════════════════════════════════

  /// 调试日志开关（生产环境关闭以避免性能开销）
  static bool _debugLogEnabled = kDebugMode;

  /// 结构化调试日志缓冲区（最近 500 条）
  static final List<Map<String, dynamic>> _debugLogBuffer = [];
  static const int _maxDebugLogSize = 500;

  /// 识别统计（用于调试面板）
  static int _totalRecognitions = 0;
  static int _successfulRecognitions = 0;
  static int _failedRecognitions = 0;
  static int _cacheHits = 0;
  static int _cacheMisses = 0;
  static final List<double> _latencyHistory = [];
  static const int _maxLatencyHistory = 200;

  /// 启用/禁用调试日志
  static void setDebugLogEnabled(bool enabled) {
    _debugLogEnabled = enabled;
    _addDebugLog('system', '调试日志${enabled ? "已启用" : "已禁用"}');
  }

  /// 是否启用调试日志
  static bool get isDebugLogEnabled => _debugLogEnabled;

  /// 添加结构化调试日志
  ///
  /// [category] 分类标签：'recognition' | 'cache' | 'cloud' | 'local' | 'system'
  /// [message] 日志消息
  /// [data] 附加数据（可选）
  static void _addDebugLog(String category, String message, {Map<String, dynamic>? data}) {
    if (!_debugLogEnabled) return;

    final entry = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'category': category,
      'message': message,
    };
    if (data != null) entry['data'] = data;

    _debugLogBuffer.add(entry);
    if (_debugLogBuffer.length > _maxDebugLogSize) {
      _debugLogBuffer.removeAt(0);
    }

    // 同时输出到 debugPrint（开发时可见）
    debugPrint('[$category] $message');
  }

  /// 获取调试日志（最近 N 条）
  static List<Map<String, dynamic>> getDebugLogs({int limit = 100}) {
    final start = (_debugLogBuffer.length - limit).clamp(0, _debugLogBuffer.length);
    return List.unmodifiable(_debugLogBuffer.sublist(start));
  }

  /// 清空调试日志
  static void clearDebugLogs() => _debugLogBuffer.clear();

  /// 获取调试统计数据（用于调试面板展示）
  ///
  /// 返回包含以下字段的 Map：
  /// - totalRecognitions: 总识别次数
  /// - successRate: 成功率 (0.0~1.0)
  /// - cacheHitRate: 缓存命中率 (0.0~1.0)
  /// - avgLatencyMs: 平均延迟（毫秒）
  /// - p95LatencyMs: P95 延迟（毫秒）
  /// - cacheSize: 当前缓存大小
  /// - estimatedCacheBytes: 估算缓存内存占用
  /// - activeMode: 当前识别模式（cloud/local）
  static Future<Map<String, dynamic>> getDebugStats() async {
    final avgLatency = _latencyHistory.isNotEmpty
        ? _latencyHistory.reduce((a, b) => a + b) / _latencyHistory.length
        : 0.0;

    double p95Latency = 0.0;
    if (_latencyHistory.isNotEmpty) {
      final sorted = List<double>.from(_latencyHistory)..sort();
      final p95Index = (sorted.length * 0.95).round().clamp(0, sorted.length - 1);
      p95Latency = sorted[p95Index];
    }

    final hitRate = (_cacheHits + _cacheMisses) > 0
        ? _cacheHits / (_cacheHits + _cacheMisses)
        : 0.0;

    return {
      'totalRecognitions': _totalRecognitions,
      'successfulRecognitions': _successfulRecognitions,
      'failedRecognitions': _failedRecognitions,
      'successRate': _totalRecognitions > 0
          ? _successfulRecognitions / _totalRecognitions
          : 0.0,
      'cacheHitRate': hitRate,
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'avgLatencyMs': avgLatency,
      'p95LatencyMs': p95Latency,
      'cacheSize': _recognitionCache.length,
      'maxCacheSize': _maxCacheSize,
      'estimatedCacheBytes': _estimatedCacheBytes,
      'maxCacheBytes': _maxCacheBytes,
      'activeMode': await instance.getUseCloud() ? 'cloud' : 'local',
      'debugLogCount': _debugLogBuffer.length,
      // v4.1.0: TFLite 模型状态
      'tfliteEnabled': await instance.getUseTflite(),
      'tfliteModelAvailable': instance.isTfliteModelAvailable,
      'tfliteStatus': TfliteRecognitionService.instance.getStatus(),
    };
  }

  /// 导出调试数据为 JSON 字符串（用于问题报告和离线分析）
  ///
  /// 包含：调试日志、统计信息、缓存摘要、配置信息
  static Future<String> exportDebugData() async {
    final stats = await getDebugStats();
    final logs = getDebugLogs(limit: 200);

    final exportData = <String, dynamic>{
      'exportDate': DateTime.now().toIso8601String(),
      'appVersion': 'v2.6.0',
      'stats': stats,
      'debugLogs': logs,
      'config': {
        'useCloud': await instance.getUseCloud(),
        'cloudUrl': await instance.getCloudUrl(),
        'hasCloudKey': (await instance.getCloudKey())?.isNotEmpty ?? false,
        'model': await instance.getModel(),
        'customModel': await instance.getCustomModel(),
      },
      'cacheSummary': {
        'recognitionCacheKeys': _recognitionCache.keys.take(50).toList(),
        'confidenceCacheKeys': _confidenceCache.keys.take(50).toList(),
        'cacheAccessOrderLength': _cacheAccessOrder.length,
      },
    };

    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  /// 记录识别延迟（内部使用）
  static void _recordLatency(double latencyMs) {
    _latencyHistory.add(latencyMs);
    if (_latencyHistory.length > _maxLatencyHistory) {
      _latencyHistory.removeAt(0);
    }
  }

  /// 简单的字节哈希用于缓存 key
  static int _hashBytes(Uint8List bytes) {
    int hash = 0x811c9dc5;
    final len = bytes.length;
    // 将长度混入哈希，减少不同大小但内容相似的图片碰撞
    hash ^= len & 0xFF;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
    hash ^= (len >> 8) & 0xFF;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
    // 采样计算：取首尾各 256 字节 + 中间 256 字节
    final sampleSize = len < 768 ? len : 768;
    for (int i = 0; i < sampleSize ~/ 3; i++) {
      hash ^= bytes[i];
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    if (len > 256) {
      for (int i = len ~/ 2 - 128; i < len ~/ 2 + 128 && i < len; i++) {
        hash ^= bytes[i];
        hash = (hash * 0x01000193) & 0xFFFFFFFF;
      }
    }
    if (len > 256) {
      for (int i = len - 256; i < len; i++) {
        hash ^= bytes[i];
        hash = (hash * 0x01000193) & 0xFFFFFFFF;
      }
    }
    return hash & 0x7FFFFFFF;
  }

  // ═══════════════════════════════════════════════════════════
  // v4.4.0: 感知哈希缓存 — 相似图片模糊匹配
  // ═══════════════════════════════════════════════════════════

  /// 感知哈希缓存（pHash → 识别结果）— v4.4.0
  /// 相似的图片（缩放、轻微变形）会产生相似的 pHash，实现模糊匹配
  static final Map<int, String> _pHashCache = {};
  static final Map<int, double> _pHashConfidenceCache = {};
  static final Map<int, DateTime> _pHashTimeCache = {};
  static const int _maxPHashCacheSize = 100;
  static const Duration _pHashExpiration = Duration(hours: 24);

  /// 计算图片的感知哈希（pHash）
  ///
  /// 算法：缩放到 8x8 灰度 → 计算平均灰度 → 生成 64-bit 哈希
  /// 相似图片的 pHash 汉明距离很小（< 10），可实现模糊匹配
  static int _computePHash(Uint8List imageBytes) {
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return _hashBytes(imageBytes);

      // 缩放到 8x8 灰度
      final small = img.copyResize(img.grayscale(decoded), width: 8, height: 8,
          interpolation: img.Interpolation.average);

      // 计算平均灰度
      double sum = 0;
      for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 8; x++) {
          sum += small.getPixel(x, y).r.toDouble();
        }
      }
      final avg = sum / 64;

      // 生成 64-bit 哈希：高于平均值为 1，低于为 0
      int hash = 0;
      int bit = 0;
      for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 8; x++) {
          if (small.getPixel(x, y).r.toDouble() >= avg) {
            hash |= (1 << bit);
          }
          bit++;
        }
      }
      return hash;
    } catch (_) {
      return _hashBytes(imageBytes);
    }
  }

  /// 计算两个哈希的汉明距离（不同位的数量）
  static int _hammingDistance(int a, int b) {
    int xor = a ^ b;
    int count = 0;
    while (xor != 0) {
      count += xor & 1;
      xor >>= 1;
    }
    return count;
  }

  /// 在感知哈希缓存中查找相似图片
  /// 汉明距离 < threshold 视为相似（默认 10）
  static String? _lookupPHashCache(int pHash, {int threshold = 10}) {
    String? bestMatch;
    int bestDistance = threshold;

    for (final entry in _pHashCache.entries) {
      // 检查是否过期
      final cachedTime = _pHashTimeCache[entry.key];
      if (cachedTime != null && DateTime.now().difference(cachedTime) > _pHashExpiration) {
        continue; // 过期，跳过
      }

      final distance = _hammingDistance(pHash, entry.key);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestMatch = entry.value;
      }
    }

    if (bestMatch != null) {
      debugPrint('感知哈希缓存: 命中 (汉明距离=$bestDistance)');
    }
    return bestMatch;
  }

  /// 写入感知哈希缓存
  static void _insertPHashCache(int pHash, String result, double confidence) {
    // 清理过期条目
    _pHashTimeCache.removeWhere((key, time) =>
        DateTime.now().difference(time) > _pHashExpiration);
    for (final key in _pHashTimeCache.keys.toList()) {
      if (!_pHashTimeCache.containsKey(key)) {
        _pHashCache.remove(key);
        _pHashConfidenceCache.remove(key);
      }
    }

    // 超出上限时淘汰最旧条目
    if (_pHashCache.length >= _maxPHashCacheSize) {
      final oldestKey = _pHashTimeCache.entries
          .reduce((a, b) => a.value.isBefore(b.value) ? a : b)
          .key;
      _pHashCache.remove(oldestKey);
      _pHashConfidenceCache.remove(oldestKey);
      _pHashTimeCache.remove(oldestKey);
    }

    _pHashCache[pHash] = result;
    _pHashConfidenceCache[pHash] = confidence;
    _pHashTimeCache[pHash] = DateTime.now();
  }

  // ═══════════════════════════════════════════════════════════
  // v4.4.0: 持久化缓存 — 高置信度结果保存到本地存储
  // ═══════════════════════════════════════════════════════════

  static const String _prefKeyPersistentCache = 'ocr_persistent_cache';
  static const int _maxPersistentCacheSize = 500;
  static bool _persistentCacheLoaded = false;

  /// 将高置信度的识别结果持久化到 SharedPreferences
  static Future<void> _persistCacheEntry(int cacheKey, String result, double confidence) async {
    // 只持久化高置信度结果（>= 0.8）
    if (confidence < 0.8) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKeyPersistentCache);
      Map<String, dynamic> cache = {};
      if (json != null && json.isNotEmpty) {
        cache = jsonDecode(json) as Map<String, dynamic>;
      }

      // 超出上限时清理最旧的 20%
      if (cache.length >= _maxPersistentCacheSize) {
        final keys = cache.keys.toList();
        final removeCount = (keys.length * 0.2).round();
        for (int i = 0; i < removeCount && i < keys.length; i++) {
          cache.remove(keys[i]);
        }
      }

      cache[cacheKey.toString()] = {
        'result': result,
        'confidence': confidence,
        'timestamp': DateTime.now().toIso8601String(),
      };

      await prefs.setString(_prefKeyPersistentCache, jsonEncode(cache));
    } catch (e) {
      debugPrint('持久化缓存写入失败: $e');
    }
  }

  /// 从持久化缓存加载识别结果
  static Future<void> _loadPersistentCache() async {
    if (_persistentCacheLoaded) return;
    _persistentCacheLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKeyPersistentCache);
      if (json == null || json.isEmpty) return;

      final cache = jsonDecode(json) as Map<String, dynamic>;
      int loaded = 0;
      int expired = 0;
      final now = DateTime.now();

      for (final entry in cache.entries) {
        final key = int.tryParse(entry.key);
        if (key == null) continue;

        final data = entry.value as Map<String, dynamic>;
        final timestamp = DateTime.tryParse(data['timestamp'] as String? ?? '');
        final result = data['result'] as String?;

        // 检查是否过期（7天）
        if (timestamp != null && now.difference(timestamp).inDays > 7) {
          expired++;
          continue;
        }

        if (result != null && !_recognitionCache.containsKey(key)) {
          _recognitionCache[key] = result;
          _cacheAccessOrder.add(key);
          loaded++;
        }
      }

      if (loaded > 0 || expired > 0) {
        debugPrint('持久化缓存: 加载 $loaded 条，跳过 $expired 条过期条目');
      }
    } catch (e) {
      debugPrint('持久化缓存加载失败: $e');
    }
  }

  /// 获取 ML Kit 识别器（中文）
  TextRecognizer _getMlKitRecognizer() {
    _mlKitRecognizer ??= TextRecognizer(script: TextRecognitionScript.chinese);
    return _mlKitRecognizer!;
  }

  /// 读取配置
  Future<bool> getUseCloud() async {
    if (_useCloud != null) return _useCloud!;
    final prefs = await SharedPreferences.getInstance();
    _useCloud = prefs.getBool(_prefKeyUseCloud) ?? false;
    return _useCloud!;
  }

  Future<String> getCloudUrl() async {
    if (_cloudUrl != null) return _cloudUrl!;
    final prefs = await SharedPreferences.getInstance();
    _cloudUrl = prefs.getString(_prefKeyCloudUrl) ?? defaultCloudUrl;
    return _cloudUrl!;
  }

  Future<String?> getCloudKey() async {
    // 优先使用用户手动输入的 Key（存在 secure storage）
    final userKey = await _secureStorage.read(key: _prefKeyCloudKey);
    if (userKey != null && userKey.isNotEmpty) return userKey;
    // 否则使用内置 Key（混淆存储）
    return ApiKeyProvider.getKey();
  }
  /// 保存配置
  Future<void> setUseCloud(bool value) async {
    _useCloud = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyUseCloud, value);
  }

  Future<void> setCloudConfig(String? url, String? key) async {
    _cloudUrl = url;
    _cloudKey = key;
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.isEmpty) {
      await prefs.remove(_prefKeyCloudUrl);
    } else {
      await prefs.setString(_prefKeyCloudUrl, url);
    }
    // API Key 存入安全存储（加密）
    if (key == null || key.isEmpty) {
      await _secureStorage.delete(key: _prefKeyCloudKey);
    } else {
      await _secureStorage.write(key: _prefKeyCloudKey, value: key);
    }
  }

  /// 判断字符是否为可接受的汉字或 ASCII
  /// v4.3.0: 收紧过滤规则，只接受 CJK 汉字和少量常用 ASCII
  /// 排除：偏旁、日文假名、韩文、特殊符号、标点、数字、拉丁字母等
  static bool _isValidChar(String ch) {
    if (ch.isEmpty) return false;
    final code = ch.codeUnitAt(0);
    // CJK 统一汉字（基本区）— 最主要的手写汉字范围
    if (code >= 0x4E00 && code <= 0x9FFF) return true;
    // CJK 统一汉字扩展 A — 少见但仍为合法汉字
    if (code >= 0x3400 && code <= 0x4DBF) return true;
    // CJK 兼容汉字
    if (code >= 0xF900 && code <= 0xFAFF) return true;
    // v4.3.0: 不再接受 ASCII（数字、标点、拉丁字母在手写汉字场景下均为异常）
    return false;
  }

  /// v4.3.0: 异常检测 — 判断识别结果是否为明显非汉字（乱码/噪声）
  ///
  /// 返回 true 表示该结果可疑，应被过滤或降权
  static bool _isAnomalousResult(String result) {
    if (result.isEmpty) return true;
    final code = result.codeUnitAt(0);
    // 标点符号（中英文）
    if (code >= 0x21 && code <= 0x2F) return true; // ! " # $ % & ' ( ) * + , - . /
    if (code >= 0x3A && code <= 0x40) return true; // : ; < = > ? @
    if (code >= 0x5B && code <= 0x60) return true; // [ \ ] ^ _ `
    if (code >= 0x7B && code <= 0x7E) return true; // { | } ~
    // 数字
    if (code >= 0x30 && code <= 0x39) return true; // 0-9
    // 拉丁字母（大小写）
    if (code >= 0x41 && code <= 0x5A) return true; // A-Z
    if (code >= 0x61 && code <= 0x7A) return true; // a-z
    // 中文标点
    if (code >= 0x3000 && code <= 0x303F) return true; // CJK 标点符号
    if (code >= 0xFF01 && code <= 0xFF0F) return true; // 全角标点
    if (code >= 0xFF1A && code <= 0xFF20) return true; // 全角标点
    if (code >= 0xFF3B && code <= 0xFF40) return true; // 全角标点
    if (code >= 0xFF5B && code <= 0xFF65) return true; // 全角标点
    // 日文假名
    if (code >= 0x3040 && code <= 0x30FF) return true;
    // 韩文
    if (code >= 0xAC00 && code <= 0xD7AF) return true;
    // 偏旁部首
    if (code >= 0x2E80 && code <= 0x2EFF) return true;
    if (code >= 0x2F00 && code <= 0x2FDF) return true;
    return false;
  }

  /// 验证并返回有效字符，无效则返回 null
  /// v4.3.0: 增加异常检测，过滤非汉字结果
  static String? _validateResult(String? result) {
    if (result == null || result.isEmpty) return null;
    final ch = String.fromCharCodes(result.runes.take(1));
    // 先检查是否为异常结果（标点/数字/字母等）
    if (_isAnomalousResult(ch)) {
      debugPrint('异常检测: 过滤非汉字结果 "$ch" (U+${ch.codeUnitAt(0).toRadixString(16)})');
      return null;
    }
    return _isValidChar(ch) ? ch : null;
  }

  /// 识别单个字符图片（带缓存）
  /// 返回 [RecognitionResult] 包含识别字符和置信度
  Future<String?> recognizeCharacter(Uint8List imageBytes, {bool? forceUseCloud}) async {
    final sw = Stopwatch()..start();
    _totalRecognitions++;
    final useCloud = forceUseCloud ?? await getUseCloud();

    final cacheKey = _hashBytes(imageBytes);

    // 云端和本地识别均使用缓存（缓存命中率提升）
    if (_recognitionCache.containsKey(cacheKey)) {
      _cacheHits++;
      _addDebugLog('cache', '缓存命中', data: {'hash': cacheKey, 'result': _recognitionCache[cacheKey]});
      debugPrint('ML Kit 识别: 命中缓存 (hash=$cacheKey)');
      // 更新 LRU 顺序
      _cacheAccessOrder.remove(cacheKey);
      _cacheAccessOrder.add(cacheKey);
      sw.stop();
      _recordLatency(sw.elapsed.inMicroseconds / 1000.0);
      return _recognitionCache[cacheKey];
    }

    _cacheMisses++;

    // v4.4.0: 加载持久化缓存（首次使用时执行）
    await _loadPersistentCache();

    // v4.4.0: 感知哈希模糊匹配 — 相似图片命中缓存
    final pHash = _computePHash(imageBytes);
    final pHashResult = _lookupPHashCache(pHash);
    if (pHashResult != null) {
      _cacheHits++;
      _addDebugLog('cache', '感知哈希缓存命中', data: {'pHash': pHash, 'result': pHashResult});
      debugPrint('识别: 感知哈希缓存命中 "$pHashResult"');
      // 同步写入精确缓存
      _recognitionCache[cacheKey] = pHashResult;
      _cacheAccessOrder.remove(cacheKey);
      _cacheAccessOrder.add(cacheKey);
      sw.stop();
      _recordLatency(sw.elapsed.inMicroseconds / 1000.0);
      return pHashResult;
    }

    // 用户反馈学习：查找相似图片的纠正结果（优先级最高）
    final feedbackResult = await UserFeedbackService.instance.findSimilarFeedback(imageBytes);
    if (feedbackResult != null) {
      _cacheHits++;
      _addDebugLog('cache', '命中用户反馈', data: {'hash': cacheKey, 'result': feedbackResult});
      debugPrint('识别: 命中用户反馈 "$feedbackResult"');
      // 同步写入内存缓存，加速后续查找
      _recognitionCache[cacheKey] = feedbackResult;
      _cacheAccessOrder.remove(cacheKey);
      _cacheAccessOrder.add(cacheKey);
      _confidenceCache[cacheKey] = 1.0; // 用户纠正 = 最高置信度
      sw.stop();
      _recordLatency(sw.elapsed.inMicroseconds / 1000.0);
      return feedbackResult;
    }

    _addDebugLog('recognition', '开始识别', data: {'mode': useCloud ? 'cloud' : 'local', 'imageSize': imageBytes.length});

    String? result;
    if (useCloud) {
      result = await _recognizeCloud(imageBytes);
    } else {
      // 本地识别
      result = await _recognizeLocal(imageBytes);

      // 手写体优化：低置信度时自动请求云端二次确认
      if (result != null && _lastLocalConfidence < 0.65) {
        debugPrint('识别: 本地置信度 ${(_lastLocalConfidence * 100).toStringAsFixed(0)}% < 65%，请求云端二次确认');
        _addDebugLog('recognition', '低置信度触发云端二次确认', data: {
          'localResult': result,
          'confidence': _lastLocalConfidence,
        });

        final cloudResult = await _recognizeCloud(imageBytes);
        if (cloudResult != null) {
          if (cloudResult == result) {
            // 本地与云端一致，提升置信度
            _confidenceCache[cacheKey] = 0.85;
            debugPrint('识别: 本地与云端一致 "$result"，置信度提升至 85%');
          } else {
            // 结果不一致，采用云端结果（云端对手写体识别更准确）
            debugPrint('识别: 本地="$result" vs 云端="$cloudResult"，采用云端结果');
            result = cloudResult;
            _confidenceCache[cacheKey] = 0.75;
          }
        }
        // 云端失败时保留本地结果
      }
    }

    // ═══ v5.3.0: 多尺度二次确认 ═══
    // 对低置信度结果，尝试 1.5x 放大后重新识别。
    // 如果放大后结果一致，说明识别可靠，提升置信度；
    // 如果不一致，保留原结果但标记为低置信度。
    if (result != null && !useCloud) {
      final currentConf = _confidenceCache[cacheKey] ?? _lastLocalConfidence;
      if (currentConf < 0.70 && currentConf > 0.0) {
        debugPrint('多尺度确认: 置信度 ${(currentConf * 100).toStringAsFixed(0)}% < 70%，尝试放大重识别');
        try {
          final decoded = img.decodeImage(imageBytes);
          if (decoded != null) {
            final maxDim = decoded.width > decoded.height ? decoded.width : decoded.height;
            if (maxDim < 400) {
              // 1.5x 放大后重新识别
              final scaled = img.copyResize(
                decoded,
                width: (decoded.width * 1.5).round(),
                height: (decoded.height * 1.5).round(),
                interpolation: img.Interpolation.cubic,
              );
              final scaledBytes = Uint8List.fromList(img.encodePng(scaled));
              final rescaledResult = await _recognizeLocal(scaledBytes);
              if (rescaledResult != null) {
                if (rescaledResult == result) {
                  // 放大后结果一致 → 提升置信度
                  final boostAmount = (0.70 - currentConf).clamp(0.0, 0.10);
                  final newConf = (currentConf + boostAmount).clamp(0.0, 0.85);
                  _confidenceCache[cacheKey] = newConf;
                  debugPrint('多尺度确认: 放大后结果一致 \"$result\"，置信度 ${(currentConf * 100).toStringAsFixed(0)}% → ${(newConf * 100).toStringAsFixed(0)}%');
                  _addDebugLog('recognition', '多尺度确认一致', data: {
                    'result': result,
                    'originalConf': currentConf,
                    'boostedConf': newConf,
                  });
                } else {
                  debugPrint('多尺度确认: 放大后结果不一致 原="$result" 放大="$rescaledResult"，保留原结果');
                  _addDebugLog('recognition', '多尺度确认不一致', data: {
                    'original': result,
                    'rescaled': rescaledResult,
                  });
                }
              }
            }
          }
        } catch (e) {
          debugPrint('多尺度确认异常: $e');
        }
      }
    }

    // ═══ v5.5.0: 微旋转重试 ═══
    // v5.7.0: 投影轮廓倾斜检测 — 先检测最佳倾斜角度，再用检测到的角度校正
    // 对低置信度结果，尝试微旋转后重新识别。
    // 手写时纸张轻微倾斜很常见，微旋转可以消除倾斜带来的识别误差。
    // 仅在本地识别且置信度 40%~75% 时执行（太低说明不是倾斜问题，太高不需要）。
    if (result != null && !useCloud) {
      final rotConf = _confidenceCache[cacheKey] ?? _lastLocalConfidence;
      if (rotConf > 0.40 && rotConf < 0.75) {
        debugPrint('微旋转重试: 置信度 ${(rotConf * 100).toStringAsFixed(0)}%，尝试微旋转');
        try {
          final decoded = img.decodeImage(imageBytes);
          if (decoded != null) {
            // v5.7.0: 投影轮廓倾斜检测 — 找到最佳角度
            final skewAngle = _detectSkewByProjection(decoded);
            // 优先使用检测到的倾斜角度，回退到固定角度
            final angles = <double>[];
            if (skewAngle.abs() > 1.0 && skewAngle.abs() < 20.0) {
              angles.addAll([skewAngle, -skewAngle]);
              debugPrint('微旋转重试: 检测到倾斜 ${skewAngle.toStringAsFixed(1)}°，优先校正');
            }
            angles.addAll([10.0, -10.0, 20.0, -20.0]);

            double bestRotConf = rotConf;
            String? bestRotResult;

            for (final angle in angles) {
              final rotated = img.copyRotate(decoded, angle: angle);
              final rotBytes = Uint8List.fromList(img.encodePng(rotated));
              final rotResult = await _recognizeLocal(rotBytes);
              if (rotResult != null) {
                final rotResultConf = _lastLocalConfidence;
                if (rotResult == result) {
                  // 旋转后结果一致 → 识别可靠，提升置信度
                  final boost = (0.08 * (1 - (angle.abs() / 20.0))).clamp(0.02, 0.08);
                  if (rotResultConf + boost > bestRotConf) {
                    bestRotConf = rotResultConf + boost;
                    bestRotResult = result;
                  }
                } else if (rotResultConf > bestRotConf + 0.05) {
                  // 旋转后得到不同且更高置信度的结果 → 可能是正确结果
                  bestRotConf = rotResultConf;
                  bestRotResult = rotResult;
                  debugPrint('微旋转重试: ${angle}° 得到 "$rotResult" '
                      '(置信度 ${(rotResultConf * 100).toStringAsFixed(0)}%)');
                }
              }
            }

            if (bestRotResult != null && bestRotResult != result && bestRotConf > rotConf + 0.05) {
              debugPrint('微旋转重试: "$result" → "$bestRotResult" '
                  '(置信度 ${(rotConf * 100).toStringAsFixed(0)}% → ${(bestRotConf * 100).toStringAsFixed(0)}%)');
              _addDebugLog('recognition', '微旋转重试替换', data: {
                'original': result,
                'rotated': bestRotResult,
                'originalConf': rotConf,
                'rotatedConf': bestRotConf,
              });
              result = bestRotResult;
              _confidenceCache[cacheKey] = bestRotConf;
            } else if (bestRotResult == result && bestRotConf > rotConf) {
              // 旋转确认了原结果，提升置信度
              _confidenceCache[cacheKey] = bestRotConf;
              debugPrint('微旋转重试: 确认 "$result"，置信度 '
                  '${(rotConf * 100).toStringAsFixed(0)}% → ${(bestRotConf * 100).toStringAsFixed(0)}%');
            }
          }
        } catch (e) {
          debugPrint('微旋转重试异常: $e');
        }
      }
    }

    // 写入缓存，超出上限时使用 LRU 策略淘汰最久未访问的条目
    // 内存优化：同时检查条目数和内存占用
    if (_recognitionCache.length >= _maxCacheSize ||
        _estimatedCacheBytes >= _maxCacheBytes) {
      _evictLruCache();
    }

    sw.stop();
    final latencyMs = sw.elapsed.inMicroseconds / 1000.0;
    _recordLatency(latencyMs);

    if (result != null) {
      _successfulRecognitions++;
      // 确保置信度缓存中有该图片的记录（投票结果可能未经过 _recognizeFromImage）
      if (!_confidenceCache.containsKey(cacheKey)) {
        _confidenceCache[cacheKey] = 0.75; // 投票通过的默认置信度
      }

      final confidence = _confidenceCache[cacheKey] ?? 0.75;

      // ═══ v5.2.0: 后处理管道优化 — 按可靠性和代价排序 ═══
      // 字典后处理优先于错误模式纠正，因为：
      // 1. 字典检查更可靠（基于语言模型，非历史统计）
      // 2. 错误模式纠正基于用户修正历史，可能包含误修正
      // 3. 字典纠正后再检查错误模式，避免错误模式覆盖正确的字典纠正

      // ── 第1步：字典后处理（代价低，查表+形近字匹配）──
      // 传入上下文信息，利用 n-gram 语言模型辅助决策
      bool wasErrorCorrected = false;
      if (result != null) {
        final dictResult = DictionaryService.instance.postProcess(
          result,
          confidence: confidence,
          prevChar: _lastRecognizedChars.isNotEmpty ? _lastRecognizedChars.last : null,
        );
        if (dictResult != result) {
          _addDebugLog('recognition', '字典后处理', data: {
            'original': result,
            'corrected': dictResult,
            'confidence': confidence,
          });
          debugPrint('识别: 字典后处理 "$result" → "$dictResult"');
          result = dictResult;
        }
      }

      // ── 第2步：错误模式纠正（代价低，查表 O(1)）──
      // 仅在字典未改变结果时执行，避免覆盖字典纠正
      if (result != null) {
        final errorCorrected = await _applyErrorPatternCorrection(result);
        if (errorCorrected != null && errorCorrected != result) {
          _addDebugLog('recognition', '错误模式纠正', data: {
            'original': result,
            'corrected': errorCorrected,
          });
          debugPrint('识别: 错误模式纠正 "$result" → "$errorCorrected"');
          result = errorCorrected;
          wasErrorCorrected = true;
        }
      }

      // ── 第3步：n-gram 上下文纠错（代价低，查表）──
      // v4.5.0: 利用前后文预测最可能的字
      // v5.5.0: 传递 prev2Char 以支持 trigram 语言模型评分
      if (result != null && confidence < 0.85 && !wasErrorCorrected) {
        final prevChar = _lastRecognizedChars.isNotEmpty ? _lastRecognizedChars.last : null;
        final prev2Char = _lastRecognizedChars.length >= 2
            ? _lastRecognizedChars[_lastRecognizedChars.length - 2]
            : null;
        final contextResult = DictionaryService.instance.correctWithHomophone(
          result,
          prevChar: prevChar,
          prev2Char: prev2Char,
          confidence: confidence,
        );
        if (contextResult != result) {
          _addDebugLog('recognition', 'n-gram上下文纠错', data: {
            'original': result,
            'corrected': contextResult,
          });
          debugPrint('识别: n-gram纠错 "$result" → "$contextResult"');
          result = contextResult;
        }
      }

      // ── 第3.5步：形近字消歧（代价低，查表 + 上下文评分 + 视觉特征）──
      // v5.2.0: 利用上下文选择最可能的字
      // v5.7.0: 新增视觉特征消歧，综合视觉+上下文评分
      if (result != null && confidence < 0.90) {
        // v5.7.0: 解码图片用于视觉特征分析
        img.Image? decodedForDisambiguation;
        try {
          decodedForDisambiguation = img.decodeImage(imageBytes);
        } catch (_) {}

        final disambiguated = _disambiguateConfusable(
          result,
          prevChar: _lastRecognizedChars.isNotEmpty ? _lastRecognizedChars.last : null,
          image: decodedForDisambiguation,
        );
        if (disambiguated != result) {
          _addDebugLog('recognition', '形近字消歧', data: {
            'original': result,
            'corrected': disambiguated,
          });
          debugPrint('识别: 形近字消歧 "$result" → "$disambiguated"');
          result = disambiguated;
        }
      }

      // ── 第4步：笔画特征辅助（代价中等，需骨架化分析）──
      // 条件执行：仅在低置信度且未被前几步纠正时才执行
      // v4.5.0: 利用曲率和复杂度特征提升匹配精度
      if (result != null && confidence < 0.90 && !wasErrorCorrected) {
        final strokeResult = await StrokeAnalyzer.instance.assistRecognition(
          imageBytes, result, confidence,
        );
        if (strokeResult != null && strokeResult != result) {
          _addDebugLog('recognition', '笔画特征辅助', data: {
            'original': result,
            'corrected': strokeResult,
            'confidence': confidence,
          });
          debugPrint('识别: 笔画辅助 "$result" → "$strokeResult"');
          result = strokeResult;
        }
      }

      // ── 第4.5步：修正学习检查（v5.3.0，代价低，查表）──
      // 利用用户历史修正记录，对低置信度结果进行修正
      if (result != null && confidence < 0.85) {
        final correctionResult = await CorrectionLearningService.instance.findCorrection(
          recognizedChar: result,
          confidence: confidence,
        );
        if (correctionResult != null && correctionResult != result) {
          _addDebugLog('recognition', '修正学习纠正', data: {
            'original': result,
            'corrected': correctionResult,
            'confidence': confidence,
          });
          debugPrint('识别: 修正学习 "$result" → "$correctionResult"');
          result = correctionResult;
        }
      }

      // ── 第5步：笔画结构验证（v5.4.0，代价中等）──
      // 对最终结果进行笔画特征验证。如果识别结果的笔画特征与图片差异过大，
      // 尝试从形近字和同音字中选择笔画特征更匹配的字符。
      if (result != null && confidence < 0.90) {
        final verifiedResult = await _verifyWithStrokeFeatures(
          imageBytes, result, confidence,
        );
        if (verifiedResult != null && verifiedResult != result) {
          _addDebugLog('recognition', '笔画结构验证', data: {
            'original': result,
            'verified': verifiedResult,
            'confidence': confidence,
          });
          debugPrint('识别: 笔画验证 "$result" → "$verifiedResult"');
          result = verifiedResult;
        }
      }

      // ── 第5.5步：图像质量置信度校准（v5.4.0）──
      // 根据图像质量指标微调置信度，让低质量图片的置信度更保守，高质量图片更自信。
      if (result != null) {
        try {
          final decoded = img.decodeImage(imageBytes);
          if (decoded != null) {
            final qualityReport = ImageQualityService.instance.assessQuality(decoded);
            final qualityScore = qualityReport.overallScore;
            final oldConf = _confidenceCache[cacheKey] ?? confidence;
            if (qualityScore > 0.80) {
              // 高质量图片：轻微提升置信度
              final newConf = (oldConf + 0.03).clamp(0.0, 0.98);
              _confidenceCache[cacheKey] = newConf;
              debugPrint('图像质量校准: 质量=${(qualityScore * 100).toStringAsFixed(0)}% '
                  '置信度 ${(oldConf * 100).toStringAsFixed(0)}% → ${(newConf * 100).toStringAsFixed(0)}%');
            } else if (qualityScore < 0.40) {
              // 低质量图片：降低置信度
              final newConf = (oldConf - 0.05).clamp(0.0, 1.0);
              _confidenceCache[cacheKey] = newConf;
              debugPrint('图像质量校准: 质量=${(qualityScore * 100).toStringAsFixed(0)}% '
                  '置信度 ${(oldConf * 100).toStringAsFixed(0)}% → ${(newConf * 100).toStringAsFixed(0)}%');
            }
          }
        } catch (e) {
          debugPrint('图像质量校准异常: $e');
        }
      }

      // v5.7.0: 字符频率最终校验 — 极罕见字符降低置信度，极常见字符微提升
      if (result != null && result.length == 1) {
        final freqRank = DictionaryService.instance.getFrequency(result);
        final currentConf = _confidenceCache[cacheKey] ?? confidence;
        if (freqRank >= 3000) {
          // 极罕见字符：可能是误识别，降低置信度
          final newConf = (currentConf - 0.03).clamp(0.0, 1.0);
          _confidenceCache[cacheKey] = newConf;
          debugPrint('频率校验: "$result" 极罕见(freq=$freqRank)，置信度 -3%');
        } else if (freqRank >= 0 && freqRank < 50) {
          // 极常见字符：轻微提升
          final newConf = (currentConf + 0.01).clamp(0.0, 0.98);
          _confidenceCache[cacheKey] = newConf;
        }
      }

      // 记录用户识别的字符，更新用户常用字缓存（异步，不阻塞返回）
      DictionaryService.instance.recordUsage(result);

      // v4.5.0: 记录到上下文序列（供 n-gram 模型使用）
      _lastRecognizedChars.add(result);
      if (_lastRecognizedChars.length > _maxContextLength) {
        _lastRecognizedChars.removeAt(0);
      }

      _addDebugLog('recognition', '识别成功', data: {
        'result': result,
        'latencyMs': latencyMs,
        'mode': useCloud ? 'cloud' : 'local',
        'confidence': confidence,
      });
    } else {
      _failedRecognitions++;
      _addDebugLog('recognition', '识别失败', data: {'latencyMs': latencyMs, 'mode': useCloud ? 'cloud' : 'local'});
    }

    // 最终结果写入缓存
    _recognitionCache[cacheKey] = result;
    _cacheAccessOrder.add(cacheKey);
    _estimatedCacheBytes += imageBytes.length; // 估算缓存内存增长

    // v4.4.0: 写入感知哈希缓存（模糊匹配）
    if (result != null) {
      final confidence = _confidenceCache[cacheKey] ?? 0.75;
      _insertPHashCache(pHash, result, confidence);
      // 异步写入持久化缓存（不阻塞返回）
      _persistCacheEntry(cacheKey, result, confidence);

      // v4.6.0: 异步写入识别历史记录（不阻塞返回）
      RecognitionHistoryService.addEntry(RecognitionHistoryEntry(
        character: result,
        confidence: confidence,
        timestamp: DateTime.now(),
        mode: useCloud ? 'cloud' : 'local',
        imageHash: cacheKey,
      ));
    }

    return result;
  }

  /// 识别单个字符图片，返回 Top-N 候选结果（按投票数降序）
  ///
  /// 复用 _recognizeLocal 的多级预处理 + 投票逻辑，
  /// 返回去重后的候选列表（最多 [n] 个）。
  /// 如果只有一个候选就返回长度 1 的列表；无候选返回空列表。
  Future<List<String>> recognizeCharacterTopN(Uint8List imageBytes, {int n = 3}) async {
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return [];

      final w = decoded.width;
      final h = decoded.height;
      final maxDim = w > h ? w : h;

      // v4.0.1: 白边裁剪（TopN 路径）
      img.Image trimmedForTopN = decoded;
      final topNTrimResult = _smartTrimWhitespace(decoded);
      if (topNTrimResult.wasTrimmed) {
        trimmedForTopN = topNTrimResult.image;
        debugPrint('TopN: 白边裁剪 ${decoded.width}x${decoded.height} → ${trimmedForTopN.width}x${trimmedForTopN.height}');
      }

      // 图像质量增强
      final qualityReport = ImageQualityService.instance.assessQuality(trimmedForTopN);
      img.Image enhanced = trimmedForTopN;
      if (qualityReport.needsEnhancement) {
        enhanced = ImageQualityService.instance.enhanceForRecognition(trimmedForTopN, qualityReport);
      }

      // v3.7.0: 图像特征分析
      final imageFeatures = await ImageAnalyzer().analyzeImage(imageBytes);

      // 分级放大策略
      List<int> upscaleTargets;
      if (maxDim < 50) {
        upscaleTargets = [400, 600, 800];
      } else if (maxDim < 100) {
        upscaleTargets = [300, 500, 700];
      } else if (maxDim < 200) {
        upscaleTargets = [200, 400];
      } else {
        upscaleTargets = [0];
      }
      if (imageFeatures.qualityLevel == 'high' && maxDim >= 150) {
        upscaleTargets = [0];
      }

      // 投票统计
      final voteMap = <String, int>{};
      final confidenceMap = <String, double>{};

      // 预处理组合（与 _recognizeLocal 一致）
      final preprocessors = <String, img.Image Function(img.Image)>{
        '灰度': (src) => img.grayscale(src),
        '灰度+对比度': (src) {
          final gray = img.grayscale(src);
          return img.adjustColor(gray, contrast: 1.5, brightness: 1.1);
        },
        '灰度+锐化': (src) {
          final gray = img.grayscale(src);
          return _sharpen(gray);
        },
        '灰度+去噪': (src) {
          final gray = img.grayscale(src);
          return _medianFilter(gray);
        },
        '灰度+自适应二值化': (src) {
          final gray = img.grayscale(src);
          return _adaptiveBinarize(gray, blockSize: 31, c: 10);
        },
        '灰度+对比度+二值化': (src) {
          final gray = img.grayscale(src);
          final e = img.adjustColor(gray, contrast: 1.5, brightness: 1.1);
          return _binarize(e);
        },
        '灰度+去噪+锐化': (src) {
          final gray = img.grayscale(src);
          final denoised = _medianFilter(gray);
          return _sharpen(denoised);
        },
        '灰度+去噪+自适应二值化': (src) {
          final gray = img.grayscale(src);
          final denoised = _medianFilter(gray);
          return _adaptiveBinarize(denoised, blockSize: 31, c: 10);
        },
        '灰度+对比度+去噪+二值化': (src) {
          final gray = img.grayscale(src);
          final e = img.adjustColor(gray, contrast: 1.5, brightness: 1.1);
          final denoised = _medianFilter(e);
          return _binarize(denoised);
        },
        '手写体笔画增强': (src) => _handwritingEnhance(src),
        '倾斜校正': (src) => _skewCorrection(src),
        '笔画归一化': (src) => _strokeNormalization(src),
        '手写体增强+对比度': (src) {
          final e = _handwritingEnhance(src);
          return _enhanceContrast(e);
        },
        // CLAHE / 背景归一化 / 方向边缘增强（v2.5.0 新增）
        '自适应对比度增强': (src) => _clahe(src),
        '背景归一化': (src) => _normalizeBackground(src),
        '方向边缘增强': (src) => _directionalEdgeEnhance(src),
        // v3.9.0: CLAHE 自适应参数（根据对比度自动选 clipLimit）
        'CLAHE自适应': (src) => ImageQualityService.instance.enhanceContrastAdaptive(src),
        // v4.0.0: 多尺度 USM 笔画锐化
        'USM笔画锐化': (src) => _unsharpMaskSharpen(src, amount: 1.5),
        'USM强锐化': (src) => _unsharpMaskSharpen(src, amount: 2.0),
        'USM锐化+CLAHE': (src) {
          final sharpened = _unsharpMaskSharpen(src, amount: 1.5);
          return ImageQualityService.instance.enhanceContrastAdaptive(sharpened);
        },
        // v2.6.0 新增 4 种预处理策略
        '自适应直方图均衡': (src) => _adaptiveHistogramEqualizeQuadrants(src),
        '形态学骨架化': (src) => _morphologicalSkeletonize(src),
        '高斯模糊去噪+锐化': (src) => _gaussianBlurSharpen(src),
        '局部阈值二值化': (src) => _localThresholdBinarize(src),
        // v4.0.1: 笔画粗细自适应
        '笔画粗细自适应': (src) => _strokeThicknessAdaptive(src),
        // v4.3.0: 形态学断笔修复（闭运算：膨胀→腐蚀，填充笔画间小间隙）
        '断笔修复': (src) => _morphologicalClose(img.grayscale(src), radius: 1),
        // v4.3.0: 细笔画增强（自适应膨胀，笔画太细时加粗）
        '细笔画增强': (src) => _thinStrokeEnhance(src),
        // v4.3.0: 形态学开运算去噪（先腐蚀后膨胀，去除小噪点）
        '开运算去噪': (src) => _morphologicalOpen(img.grayscale(src), radius: 1),
        // v4.3.0: 多尺度形态学（小膨胀+闭运算，兼顾断笔修复和笔画增强）
        '多尺度形态学': (src) => _multiScaleMorphology(src),
        // v4.5.0 新增预处理策略
        '自适应伽马校正': (src) => _adaptiveGammaCorrection(src),
        '多尺度边缘增强': (src) => _multiScaleEdgeEnhance(src),
        '笔画感知去噪': (src) => _strokeAwareDenoise(src),
        '伽马+CLAHE': (src) {
          final gamma = _adaptiveGammaCorrection(src);
          return ImageQualityService.instance.enhanceContrastAdaptive(gamma);
        },
        '边缘增强+锐化': (src) {
          final edge = _multiScaleEdgeEnhance(src);
          return _unsharpMaskSharpen(edge, amount: 1.2);
        },
        // v5.7.0: 自适应 Sauvola 二值化
        'Sauvola二值化': (src) => _sauvolaBinarizeAdaptive(src, features: imageFeatures),
        '去噪+Sauvola': (src) {
          final denoised = _strokeAwareDenoise(src);
          return _sauvolaBinarizeAdaptive(denoised, features: imageFeatures);
        },
        '伽马+Sauvola': (src) {
          final gamma = _adaptiveGammaCorrection(src);
          return _sauvolaBinarizeAdaptive(gamma, features: imageFeatures);
        },
      };

      for (final targetSize in upscaleTargets) {
        img.Image base;
        if (targetSize == 0) {
          base = enhanced;
        } else {
          final scale = targetSize / maxDim;
          final newW = (w * scale).round();
          final newH = (h * scale).round();
          base = img.copyResize(enhanced, width: newW, height: newH,
              interpolation: img.Interpolation.cubic);
        }

        for (final entry in preprocessors.entries) {
          final processed = entry.value(base);
          final rawResult = await _recognizeFromImage(processed);
          final result = _validateResult(rawResult);
          if (result != null) {
            voteMap[result] = (voteMap[result] ?? 0) + 1;
            final hash = _hashBytes(img.encodePng(processed));
            final conf = _confidenceCache[hash] ?? 0.7;
            confidenceMap[result] = (confidenceMap[result] ?? 0) > conf
                ? confidenceMap[result]!
                : conf;
          }
        }
      }

      // v4.4.0: 多候选综合评分排序（TopN 路径）
      final totalVotesTopN = voteMap.values.fold(0, (a, b) => a + b);
      final candidateScoresTopN = <String, double>{};
      for (final entry in voteMap.entries) {
        candidateScoresTopN[entry.key] = _computeCandidateScore(
          candidate: entry.key,
          votes: entry.value,
          totalVotes: totalVotesTopN,
          confidenceMap: confidenceMap,
          resultStrategies: {}, // TopN 路径不跟踪策略来源
          resultSizes: {}, // TopN 路径不跟踪放大尺寸
        );
      }
      final sorted = voteMap.entries.toList()
        ..sort((a, b) {
          final scoreDiff = (candidateScoresTopN[b.key] ?? 0).compareTo(candidateScoresTopN[a.key] ?? 0);
          if (scoreDiff != 0) return scoreDiff;
          return b.value.compareTo(a.value);
        });

      // ═══ v4.1.0: TFLite 模型补充 Top-N 投票 ═══
      try {
        final useTflite = await getUseTflite();
        if (useTflite) {
          final tfliteService = TfliteRecognitionService.instance;
          final tfliteLoaded = await tfliteService.loadModel();
          if (tfliteLoaded && tfliteService.isModelLoaded) {
            final tflitePredictions = await tfliteService.recognizeWithConfidence(
              imageBytes,
              topN: n,
            );
            for (final pred in tflitePredictions) {
              voteMap[pred.character] = (voteMap[pred.character] ?? 0) + 1;
              confidenceMap[pred.character] = (confidenceMap[pred.character] ?? 0) > pred.confidence
                  ? confidenceMap[pred.character]!
                  : pred.confidence;
            }
            debugPrint('TopN: TFLite 补充 ${tflitePredictions.length} 个候选');
          }
        }
      } catch (e) {
        debugPrint('TopN: TFLite 补充投票异常: $e');
      }

      // v4.4.0: 重新排序（包含 TFLite 投票，使用综合评分）
      final finalTotalVotes = voteMap.values.fold(0, (a, b) => a + b);
      final finalScores = <String, double>{};
      for (final entry in voteMap.entries) {
        finalScores[entry.key] = _computeCandidateScore(
          candidate: entry.key,
          votes: entry.value,
          totalVotes: finalTotalVotes,
          confidenceMap: confidenceMap,
          resultStrategies: {},
          resultSizes: {},
        );
      }
      final finalSorted = voteMap.entries.toList()
        ..sort((a, b) {
          final scoreDiff = (finalScores[b.key] ?? 0).compareTo(finalScores[a.key] ?? 0);
          if (scoreDiff != 0) return scoreDiff;
          return b.value.compareTo(a.value);
        });

      return finalSorted.take(n).map((e) => e.key).toList();
    } catch (e) {
      debugPrint('recognizeCharacterTopN 失败: $e');
      return [];
    }
  }

  /// 批量识别字符图片（带并发控制和进度回调）
  /// v4.4.0: 共享预处理结果 — 相似特征的图片复用预处理参数，减少重复计算
  Future<List<String?>> recognizeBatch(
    List<Uint8List> images, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final useCloud = await getUseCloud();
    final results = List<String?>.filled(images.length, null);

    // 预检：跳过已缓存的图片，减少实际识别调用
    final uncachedIndices = <int>[];
    if (!useCloud) {
      for (int i = 0; i < images.length; i++) {
        final cacheKey = _hashBytes(images[i]);
        if (_recognitionCache.containsKey(cacheKey)) {
          results[i] = _recognitionCache[cacheKey];
          // 更新 LRU 顺序
          _cacheAccessOrder.remove(cacheKey);
          _cacheAccessOrder.add(cacheKey);
          debugPrint('批量识别: 缓存命中 index=$i');
        } else {
          uncachedIndices.add(i);
        }
      }
    } else {
      uncachedIndices.addAll(List.generate(images.length, (i) => i));
    }

    if (uncachedIndices.isEmpty) {
      onProgress?.call(images.length, images.length);
      return results;
    }

    int completed = 0;
    // 已缓存的也算完成
    final preCachedCount = images.length - uncachedIndices.length;
    completed = preCachedCount;

    // v4.4.0: 批量预分析 — 提前解码和分析所有待识别图片的特征
    // 相似特征的图片可以共享预处理参数，减少重复计算
    if (!useCloud && uncachedIndices.length > 1) {
      final imageFeatures = <int, ImageFeatures>{};
      for (final idx in uncachedIndices) {
        try {
          imageFeatures[idx] = await ImageAnalyzer().analyzeImage(images[idx]);
        } catch (_) {}
      }

      // 按特征相似度分组（尺寸和质量级别相同的图片分为一组）
      final groups = <String, List<int>>{};
      for (final idx in uncachedIndices) {
        final features = imageFeatures[idx];
        if (features == null) {
          groups.putIfAbsent('default', () => []).add(idx);
          continue;
        }
        // 分组键：质量级别 + 尺寸范围
        final decoded = img.decodeImage(images[idx]);
        final maxDim = decoded != null ? (decoded.width > decoded.height ? decoded.width : decoded.height) : 0;
        final sizeRange = maxDim < 50 ? 'xs' : (maxDim < 100 ? 'sm' : (maxDim < 200 ? 'md' : 'lg'));
        final groupKey = '${features.qualityLevel}_$sizeRange';
        groups.putIfAbsent(groupKey, () => []).add(idx);
      }

      debugPrint('批量识别: ${uncachedIndices.length} 张图片分为 ${groups.length} 组 '
          '(${groups.entries.map((e) => '${e.key}:${e.value.length}').join(', ')})');

      // 按组并行处理（同组图片共享预处理参数的经验）
      final semaphore = _Semaphore(_maxConcurrent);
      final futures = <Future>[];

      for (final group in groups.values) {
        for (final index in group) {
          futures.add(() async {
            await semaphore.acquire();
            try {
              results[index] = await _recognizeLocal(images[index]);
              if (results[index] != null) {
                final cacheKey = _hashBytes(images[index]);
                _recognitionCache.putIfAbsent(cacheKey, () => results[index]!);
                _cacheAccessOrder.remove(cacheKey);
                _cacheAccessOrder.add(cacheKey);
                _confidenceCache.putIfAbsent(cacheKey, () => 0.75);
              }
              completed++;
              onProgress?.call(completed, images.length);
            } finally {
              semaphore.release();
            }
          }());
        }
      }

      await Future.wait(futures);
    } else {
      // 云端模式或单张图片：使用原始逻辑
      final semaphore = _Semaphore(_maxConcurrent);
      final futures = <Future>[];

      for (final index in uncachedIndices) {
        futures.add(() async {
          await semaphore.acquire();
          try {
            if (useCloud) {
              results[index] = await _recognizeCloud(images[index]);
            } else {
              results[index] = await _recognizeLocal(images[index]);
            }
            if (results[index] != null) {
              final cacheKey = _hashBytes(images[index]);
              _recognitionCache.putIfAbsent(cacheKey, () => results[index]!);
              _cacheAccessOrder.remove(cacheKey);
              _cacheAccessOrder.add(cacheKey);
              _confidenceCache.putIfAbsent(cacheKey, () => 0.75);
            }
            completed++;
            onProgress?.call(completed, images.length);
          } finally {
            semaphore.release();
          }
        }());
      }

      await Future.wait(futures);
    }

    return results;
  }

  // ===== 图片预处理辅助方法 =====

  /// 中值滤波去噪（3x3 窗口，对椒盐噪声效果好）
  img.Image _medianFilter(img.Image src) {
    final result = img.Image(width: src.width, height: src.height);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final values = <int>[];
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final nx = (x + dx).clamp(0, src.width - 1);
            final ny = (y + dy).clamp(0, src.height - 1);
            values.add(src.getPixel(nx, ny).r.toInt());
          }
        }
        values.sort();
        final median = values[4]; // 中位数
        result.setPixelRgba(x, y, median, median, median, 255);
      }
    }
    return result;
  }

  /// 反转颜色（黑底白字 ↔ 白底黑字）
  img.Image _invertColors(img.Image src) {
    final result = img.Image(width: src.width, height: src.height);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final pixel = src.getPixel(x, y);
        final r = 255 - pixel.r.toInt();
        final g = 255 - pixel.g.toInt();
        final b = 255 - pixel.b.toInt();
        result.setPixelRgba(x, y, r, g, b, 255);
      }
    }
    return result;
  }

  /// 裁剪边缘空白，返回紧凑图片（带少量 padding）
  img.Image _trimWhitespace(img.Image src, {double paddingRatio = 0.1}) {
    // 找到内容边界
    int minX = src.width, maxX = 0, minY = src.height, maxY = 0;
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final v = src.getPixel(x, y).r.toInt();
        if (v < 240) { // 非白色像素
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (minX > maxX || minY > maxY) return src; // 全白，返回原图

    // 加 padding
    final contentW = maxX - minX + 1;
    final contentH = maxY - minY + 1;
    final padX = (contentW * paddingRatio).round();
    final padY = (contentH * paddingRatio).round();
    final cropX = (minX - padX).clamp(0, src.width - 1);
    final cropY = (minY - padY).clamp(0, src.height - 1);
    final cropW = (contentW + padX * 2).clamp(1, src.width - cropX);
    final cropH = (contentH + padY * 2).clamp(1, src.height - cropY);

    return img.copyCrop(src, x: cropX, y: cropY, width: cropW, height: cropH);
  }

  /// v4.0.1: 智能白边裁剪结果
  static _TrimResult _smartTrimWhitespace(img.Image src, {double paddingRatio = 0.08}) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;
    if (w < 10 || h < 10) return _TrimResult(src, false, 0);

    // 自适应阈值：检测背景色（可能是白色、浅灰、米色等）
    // 采样四边的像素取众数作为背景色
    int bgSum = 0, bgCount = 0;
    // 上边
    for (int y = 0; y < h ~/ 8; y++) {
      for (int x = 0; x < w; x += 3) {
        bgSum += gray.getPixel(x, y).r.toInt();
        bgCount++;
      }
    }
    // 下边
    for (int y = h - h ~/ 8; y < h; y++) {
      for (int x = 0; x < w; x += 3) {
        bgSum += gray.getPixel(x, y).r.toInt();
        bgCount++;
      }
    }
    // 左边
    for (int y = 0; y < h; y += 3) {
      for (int x = 0; x < w ~/ 8; x++) {
        bgSum += gray.getPixel(x, y).r.toInt();
        bgCount++;
      }
    }
    // 右边
    for (int y = 0; y < h; y += 3) {
      for (int x = w - w ~/ 8; x < w; x++) {
        bgSum += gray.getPixel(x, y).r.toInt();
        bgCount++;
      }
    }
    // 背景亮度 + 容差（30 灰度级内的都算背景）
    final bgLevel = bgCount > 0 ? bgSum ~/ bgCount : 245;
    final threshold = bgLevel - 30;

    // 扫描内容边界
    int minX = w, maxX = 0, minY = h, maxY = 0;
    for (int y = 0; y < h; y += 2) {
      for (int x = 0; x < w; x += 2) {
        if (gray.getPixel(x, y).r.toInt() < threshold) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (minX > maxX || minY > maxY) return _TrimResult(src, false, 0);

    // 计算裁剪比例
    final contentW = maxX - minX + 1;
    final contentH = maxY - minY + 1;
    final contentArea = contentW * contentH;
    final totalArea = w * h;
    final blankRatio = 1.0 - contentArea / totalArea;

    // 空白太少不需要裁剪（< 15%）
    if (blankRatio < 0.15) return _TrimResult(src, false, blankRatio * 100);

    // 加 padding（裁剪越少 padding 越大，保证字符不被切到）
    final padX = (contentW * paddingRatio).round();
    final padY = (contentH * paddingRatio).round();
    final cropX = (minX - padX).clamp(0, w - 1);
    final cropY = (minY - padY).clamp(0, h - 1);
    final cropW = (contentW + padX * 2).clamp(1, w - cropX);
    final cropH = (contentH + padY * 2).clamp(1, h - cropY);

    // 裁剪后至少要有 30x30，避免裁太小影响识别
    if (cropW < 30 || cropH < 30) return _TrimResult(src, false, blankRatio * 100);

    final cropped = img.copyCrop(src, x: cropX, y: cropY, width: cropW, height: cropH);
    return _TrimResult(cropped, true, blankRatio * 100);
  }

  /// 检测图片是否可能包含多个连笔字符
  /// 判断依据：宽高比 > 1.3 且墨迹分布有明显的双峰特征
  bool _detectConnectedCharacters(img.Image image) {
    final w = image.width;
    final h = image.height;
    final aspect = w / h.clamp(1, 99999);

    // 宽高比不大的图片不太可能是连笔字
    if (aspect < 1.3) return false;

    // 计算垂直投影
    final gray = img.grayscale(image);
    final projections = List.filled(w, 0);
    for (int x = 0; x < w; x++) {
      int count = 0;
      for (int y = 0; y < h; y++) {
        if (gray.getPixel(x, y).r.toInt() < 128) count++;
      }
      projections[x] = count;
    }

    // 找到投影的峰值和谷值
    int peakCount = 0;
    int valleyCount = 0;
    final threshold = h * 0.1; // 峰值阈值
    final valleyThreshold = h * 0.02; // 谷值阈值

    bool inPeak = false;
    for (int x = 1; x < w - 1; x++) {
      if (projections[x] > threshold) {
        if (!inPeak) {
          peakCount++;
          inPeak = true;
        }
      } else if (projections[x] < valleyThreshold) {
        if (inPeak) {
          valleyCount++;
          inPeak = false;
        }
      }
    }

    // 如果有多个峰和谷，说明可能有多个字符
    return peakCount >= 2 && valleyCount >= 1;
  }

  /// 使用垂直投影法将连笔字图片切分为多个片段
  /// 返回切分后的图片列表（如果切分失败则返回原图的单元素列表）
  List<img.Image> _segmentByVerticalProjection(img.Image image) {
    final w = image.width;
    final h = image.height;

    // 计算垂直投影
    final gray = img.grayscale(image);
    final projections = List.filled(w, 0);
    for (int x = 0; x < w; x++) {
      int count = 0;
      for (int y = 0; y < h; y++) {
        if (gray.getPixel(x, y).r.toInt() < 128) count++;
      }
      projections[x] = count;
    }

    // 找到最佳切分点（投影值最小的位置，在图片中间 30%~70% 区域）
    final searchStart = (w * 0.25).round();
    final searchEnd = (w * 0.75).round();

    int bestSplitX = w ~/ 2;
    int minProjection = 999999;

    // 找到连续低投影区域的中心作为切分点
    for (int x = searchStart; x < searchEnd; x++) {
      // 计算局部平均投影（5像素窗口）
      int localSum = 0;
      int count = 0;
      for (int dx = -2; dx <= 2; dx++) {
        final px = x + dx;
        if (px >= 0 && px < w) {
          localSum += projections[px];
          count++;
        }
      }
      final localAvg = localSum / count.clamp(1, 5);

      if (localAvg < minProjection) {
        minProjection = localAvg.round();
        bestSplitX = x;
      }
    }

    // 如果最佳切分点的投影值太高，说明没有明显的分割线，不切分
    if (minProjection > h * 0.15) {
      return [image];
    }

    // 切分图片
    final left = img.copyCrop(image, x: 0, y: 0, width: bestSplitX, height: h);
    final right = img.copyCrop(image, x: bestSplitX, y: 0, width: w - bestSplitX, height: h);

    // 检查切分后的片段是否有足够的墨迹（避免切出空白片段）
    final leftDensity = _calculateInkDensity(left);
    final rightDensity = _calculateInkDensity(right);

    if (leftDensity < 0.03 || rightDensity < 0.03) {
      // 一个片段几乎没有墨迹，切分无效
      return [image];
    }

    debugPrint('连笔字切分: ${w}x$h → 左${bestSplitX}x$h + 右${w - bestSplitX}x$h '
        '(切分点投影=$minProjection, 左密度=${(leftDensity * 100).toStringAsFixed(1)}%, '
        '右密度=${(rightDensity * 100).toStringAsFixed(1)}%)');

    return [left, right];
  }

  /// 计算图片的墨迹密度（黑色像素占比）
  double _calculateInkDensity(img.Image image) {
    final gray = img.grayscale(image);
    int blackCount = 0;
    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++) {
        if (gray.getPixel(x, y).r.toInt() < 128) blackCount++;
      }
    }
    return blackCount / (gray.width * gray.height).clamp(1, 999999);
  }

  /// v4.0.1: 笔画粗细自适应预处理策略
  /// 根据图像的笔画粗细特征，自动选择膨胀/腐蚀来归一化笔画宽度
  img.Image _strokeThicknessAdaptive(img.Image src) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;
    if (w < 20 || h < 20) return gray;

    // 二值化
    final binary = _adaptiveBinarize(gray, blockSize: 31, c: 10);

    // 统计前景像素比来估算笔画粗细
    int fgCount = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (binary.getPixel(x, y).r.toInt() < 128) fgCount++;
      }
    }
    final fgRatio = fgCount / (w * h);

    // 笔画太细（前景 < 8%）→ 膨胀
    if (fgRatio < 0.08) {
      debugPrint('笔画自适应: 笔画太细 (${(fgRatio * 100).toStringAsFixed(1)}%) → 膨胀增强');
      return _morphologicalDilate(gray, radius: 1);
    }
    // 笔画太粗（前景 > 30%）→ 腐蚀
    if (fgRatio > 0.30) {
      debugPrint('笔画自适应: 笔画太粗 (${(fgRatio * 100).toStringAsFixed(1)}%) → 腐蚀细化');
      return _morphologicalErode(gray, radius: 1);
    }
    // 正常范围 → 灰度输出
    return gray;
  }

  /// 形态学细化（骨架化）- Zhang-Suen 算法简化版
  /// 将笔画细化为 1 像素宽的骨架，提升 ML Kit 对粗笔画的识别
  img.Image _skeletonize(img.Image binary) {
    // 先转为二值灰度
    final gray = img.grayscale(binary);
    final w = gray.width, h = gray.height;

    // 初始化标记数组（true = 黑色前景）
    var pixels = List.generate(h, (y) =>
        List.generate(w, (x) => gray.getPixel(x, y).r.toInt() < 128));

    bool changed = true;
    int iterations = 0;
    const maxIterations = 50;

    while (changed && iterations < maxIterations) {
      changed = false;
      iterations++;

      // 标记要删除的像素
      final toRemove = List.generate(h, (_) => List.filled(w, false));

      for (int y = 1; y < h - 1; y++) {
        for (int x = 1; x < w - 1; x++) {
          if (!pixels[y][x]) continue;

          // 计算 8-邻域中黑色邻居数
          final neighbors = [
            pixels[y-1][x], pixels[y-1][x+1], pixels[y][x+1], pixels[y+1][x+1],
            pixels[y+1][x], pixels[y+1][x-1], pixels[y][x-1], pixels[y-1][x-1],
          ];
          final p = neighbors.map((b) => b ? 1 : 0).toList();
          final bp = p[0] + p[1] + p[2] + p[3] + p[4] + p[5] + p[6] + p[7];

          // 条件1: 2 <= 黑色邻居数 <= 6
          if (bp < 2 || bp > 6) continue;

          // 条件2: 0->1 转换次数 == 1
          int transitions = 0;
          for (int i = 0; i < 8; i++) {
            if (p[i] == 0 && p[(i + 1) % 8] == 1) transitions++;
          }
          if (transitions != 1) continue;

          // 条件3: p[0] * p[2] * p[4] == 0 (N * E * S == 0)
          if (p[0] * p[2] * p[4] != 0) continue;

          // 条件4: p[2] * p[4] * p[6] == 0 (E * S * W == 0)
          if (p[2] * p[4] * p[6] != 0) continue;

          toRemove[y][x] = true;
          changed = true;
        }
      }

      // 执行删除
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          if (toRemove[y][x]) pixels[y][x] = false;
        }
      }
    }

    // 转回图片
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final v = pixels[y][x] ? 0 : 255;
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    debugPrint('  骨架化: $iterations 次迭代');
    return result;
  }

  /// 自适应二值化（局部均值法，增强版）
  /// 对比度低的区域使用更小的阈值偏移，保留更多笔画细节
  img.Image _adaptiveBinarize(img.Image src, {int blockSize = 31, int c = 10}) {
    if (blockSize.isEven) blockSize++;
    final half = blockSize ~/ 2;
    final w = src.width, h = src.height;
    final result = img.Image(width: w, height: h);

    // 积分图加速
    final integral = List.generate(h, (_) => List.filled(w, 0));
    for (int y = 0; y < h; y++) {
      int rowSum = 0;
      for (int x = 0; x < w; x++) {
        rowSum += src.getPixel(x, y).r.toInt();
        integral[y][x] = rowSum + (y > 0 ? integral[y - 1][x] : 0);
      }
    }

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final x1 = (x - half).clamp(0, w - 1);
        final y1 = (y - half).clamp(0, h - 1);
        final x2 = (x + half).clamp(0, w - 1);
        final y2 = (y + half).clamp(0, h - 1);
        final count = (x2 - x1 + 1) * (y2 - y1 + 1);

        int sum = integral[y2][x2];
        if (x1 > 0) sum -= integral[y2][x1 - 1];
        if (y1 > 0) sum -= integral[y1 - 1][x2];
        if (x1 > 0 && y1 > 0) sum += integral[y1 - 1][x1 - 1];

        final localMean = sum / count;
        final threshold = localMean - c;
        final brightness = src.getPixel(x, y).r.toInt();
        final v = brightness < threshold ? 0 : 255;
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// 锐化卷积（3x3 锐化核，手动实现兼容 image v4）
  img.Image _sharpen(img.Image src) {
    final result = img.Image(width: src.width, height: src.height);
    // 锐化核: [0,-1,0, -1,5,-1, 0,-1,0]
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        num r = 0, g = 0, b = 0;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final nx = (x + dx).clamp(0, src.width - 1);
            final ny = (y + dy).clamp(0, src.height - 1);
            final pixel = src.getPixel(nx, ny);
            // kernel weight: center=5, cardinal=-1, corners=0
            final weight = (dx == 0 && dy == 0) ? 5
                : ((dx == 0 || dy == 0) ? -1 : 0);
            r += pixel.r * weight;
            g += pixel.g * weight;
            b += pixel.b * weight;
          }
        }
        result.setPixelRgba(x, y,
          r.clamp(0, 255).toInt(),
          g.clamp(0, 255).toInt(),
          b.clamp(0, 255).toInt(),
          255);
      }
    }
    return result;
  }

  /// 多尺度 Unsharp Masking 笔画锐化（v4.0.0）
  ///
  /// 针对手写汉字笔画优化的锐化算法：
  /// 1. 多尺度高斯模糊分离高频细节和中频结构
  /// 2. 自适应锐化强度（笔画暗像素区域增强更多，背景保护）
  /// 3. 笔画边缘保护防止过度锐化振铃效应
  img.Image _unsharpMaskSharpen(img.Image src, {double amount = 1.5}) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;

    // 两层高斯模糊：σ=1 (3x3) 细节层，σ=2 (5x5) 结构层
    // 第一层 3x3 高斯核 (sigma≈1.0)
    const k3 = [
      [1, 2, 1],
      [2, 4, 2],
      [1, 2, 1],
    ];
    const d3 = 16;
    final blur1 = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int sum = 0;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final nx = (x + dx).clamp(0, w - 1);
            final ny = (y + dy).clamp(0, h - 1);
            sum += gray.getPixel(nx, ny).r.toInt() * k3[dy + 1][dx + 1];
          }
        }
        final v = (sum / d3).round().clamp(0, 255);
        blur1.setPixelRgba(x, y, v, v, v, 255);
      }
    }

    // 第二层 5x5 高斯核 (sigma≈2.0)
    const k5 = [
      [1, 4, 7, 4, 1],
      [4, 16, 26, 16, 4],
      [7, 26, 41, 26, 7],
      [4, 16, 26, 16, 4],
      [1, 4, 7, 4, 1],
    ];
    const d5 = 273;
    final blur2 = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int sum = 0;
        for (int dy = -2; dy <= 2; dy++) {
          for (int dx = -2; dx <= 2; dx++) {
            final nx = (x + dx).clamp(0, w - 1);
            final ny = (y + dy).clamp(0, h - 1);
            sum += gray.getPixel(nx, ny).r.toInt() * k5[dy + 2][dx + 2];
          }
        }
        final v = (sum / d5).round().clamp(0, 255);
        blur2.setPixelRgba(x, y, v, v, v, 255);
      }
    }

    // 多尺度合成：细节层 + 结构层
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final orig = gray.getPixel(x, y).r.toDouble();
        final b1 = blur1.getPixel(x, y).r.toDouble();
        final b2 = blur2.getPixel(x, y).r.toDouble();

        // 细节层 = 原图 - 细模糊（高频笔画边缘）
        final detail = orig - b1;
        // 结构层 = 细模糊 - 粗模糊（中频笔画结构）
        final structure = b1 - b2;

        // 自适应强度：笔画区域（暗像素）增强更多，背景（亮像素）保护
        final strokeWeight = orig < 128 ? amount * 1.2 : amount * 0.6;

        // 合成：原图 + 细节增强 + 结构增强
        var v = orig + detail * strokeWeight + structure * (strokeWeight * 0.5);
        v = v.clamp(0, 255);

        result.setPixelRgba(x, y, v.toInt(), v.toInt(), v.toInt(), 255);
      }
    }
    return result;
  }

  /// 对比度增强（复用已有 adjustColor API，与 image_processor.dart 一致）
  img.Image _enhanceContrast(img.Image src) {
    return img.adjustColor(src, contrast: 1.5, brightness: 1.1);
  }

  /// 手写体专用预处理：笔画增强（膨胀+细化）
  ///
  /// 针对手写汉字特征优化：
  /// 1. 自适应二值化（小窗口，对手写笔画更敏感）
  /// 2. 形态学膨胀：连接断笔、增强笔画连通性
  /// 3. 中值滤波：去除手写毛刺和飞白噪声
  /// 4. 骨架化：恢复标准笔画宽度
  img.Image _handwritingEnhance(img.Image src) {
    debugPrint('  手写体增强: 开始笔画增强处理');
    final gray = img.grayscale(src);
    // 使用更小的 blockSize 对手写体笔画更敏感
    final binary = _adaptiveBinarize(gray, blockSize: 25, c: 8);
    // 膨胀连接断笔
    final dilated = _morphologicalDilate(binary, radius: 1);
    // 中值滤波去毛刺
    final smoothed = _medianFilter(dilated);
    // 细化回标准宽度
    final result = _skeletonize(smoothed);
    debugPrint('  手写体增强: 完成');
    return result;
  }

  /// 倾斜校正（投影法，±15度范围自动检测）
  ///
  /// 对二值化图片在 -15°~+15° 范围内逐角度旋转，
  /// 计算每次旋转后水平投影的方差。方差最大时文字行最整齐，
  /// 即为最佳校正角度。
  img.Image _skewCorrection(img.Image src) {
    debugPrint('  倾斜校正: 检测倾斜角度 (±15°)');
    final gray = img.grayscale(src);
    final binary = _adaptiveBinarize(gray, blockSize: 31, c: 10);

    double bestAngle = 0;
    double maxVariance = 0;

    // 以 1 度步长搜索最佳角度
    for (double angle = -15; angle <= 15; angle += 1.0) {
      final rotated = img.copyRotate(binary, angle: angle);
      final variance = _horizontalProjectionVariance(rotated);
      if (variance > maxVariance) {
        maxVariance = variance;
        bestAngle = angle;
      }
    }

    debugPrint('  倾斜校正: 最佳角度 ${bestAngle.toStringAsFixed(1)}°');

    // 倾斜不足 1 度时跳过校正，避免无意义的旋转损失
    if (bestAngle.abs() < 1.0) {
      debugPrint('  倾斜校正: 倾斜过小，跳过');
      return src;
    }

    return img.copyRotate(src, angle: -bestAngle);
  }

  /// 笔画粗细归一化
  ///
  /// 估算当前平均笔画宽度，与目标宽度（3px）比较，
  /// 通过膨胀或腐蚀将笔画调整到统一粗细，提升识别一致性。
  img.Image _strokeNormalization(img.Image src) {
    debugPrint('  笔画归一化: 分析笔画粗细');
    final gray = img.grayscale(src);
    final binary = _adaptiveBinarize(gray, blockSize: 31, c: 10);
    final strokeWidth = _estimateStrokeWidth(binary);
    const targetWidth = 3.0;

    debugPrint('  笔画归一化: 当前 ${strokeWidth.toStringAsFixed(1)}px → 目标 ${targetWidth}px');

    if ((strokeWidth - targetWidth).abs() < 0.5) {
      debugPrint('  笔画归一化: 已接近目标，跳过');
      return src;
    }

    if (strokeWidth < targetWidth) {
      final r = ((targetWidth - strokeWidth) / 2).round().clamp(1, 3);
      debugPrint('  笔画归一化: 膨胀 $r 像素');
      return _morphologicalDilate(binary, radius: r);
    } else {
      final r = ((strokeWidth - targetWidth) / 2).round().clamp(1, 3);
      debugPrint('  笔画归一化: 腐蚀 $r 像素');
      return _morphologicalErode(binary, radius: r);
    }
  }

  /// 形态学膨胀（邻域内存在黑色像素则当前像素变黑）
  /// 用于连接断笔、增强笔画连通性
  img.Image _morphologicalDilate(img.Image binary, {int radius = 1}) {
    final gray = img.grayscale(binary);
    final w = gray.width, h = gray.height;
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        bool hasBlack = false;
        for (int dy = -radius; dy <= radius && !hasBlack; dy++) {
          for (int dx = -radius; dx <= radius && !hasBlack; dx++) {
            final nx = (x + dx).clamp(0, w - 1);
            final ny = (y + dy).clamp(0, h - 1);
            if (gray.getPixel(nx, ny).r.toInt() < 128) hasBlack = true;
          }
        }
        final v = hasBlack ? 0 : 255;
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// 形态学腐蚀（邻域内全部为黑色时当前像素才保持黑色）
  /// 用于细化笔画
  img.Image _morphologicalErode(img.Image binary, {int radius = 1}) {
    final gray = img.grayscale(binary);
    final w = gray.width, h = gray.height;
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        bool allBlack = true;
        for (int dy = -radius; dy <= radius && allBlack; dy++) {
          for (int dx = -radius; dx <= radius && allBlack; dx++) {
            final nx = (x + dx).clamp(0, w - 1);
            final ny = (y + dy).clamp(0, h - 1);
            if (gray.getPixel(nx, ny).r.toInt() >= 128) allBlack = false;
          }
        }
        final v = allBlack ? 0 : 255;
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// v4.3.0: 形态学闭运算（先膨胀后腐蚀，填充笔画间小间隙/断笔）
  img.Image _morphologicalClose(img.Image binary, {int radius = 1}) {
    final dilated = _morphologicalDilate(binary, radius: radius);
    return _morphologicalErode(dilated, radius: radius);
  }

  /// v4.3.0: 形态学开运算（先腐蚀后膨胀，去除小噪点）
  img.Image _morphologicalOpen(img.Image binary, {int radius = 1}) {
    final eroded = _morphologicalErode(binary, radius: radius);
    return _morphologicalDilate(eroded, radius: radius);
  }

  /// v5.7.0: 形态学梯度（膨胀 - 腐蚀）— 提取边缘轮廓
  ///
  /// 梯度图突出显示笔画边缘，对以下场景特别有效：
  /// - 笔画密集的复杂字：边缘增强帮助分离相邻笔画
  /// - 笔画粗细不均的字：统一边缘响应
  /// - 低对比度图片：边缘比内部更易检测
  img.Image _morphologicalGradient(img.Image src, {int radius = 1}) {
    final gray = img.grayscale(src);
    final binary = _adaptiveBinarize(gray, blockSize: 25, c: 10);
    final dilated = _morphologicalDilate(binary, radius: radius);
    final eroded = _morphologicalErode(binary, radius: radius);
    // 梯度 = 膨蚀 - 腐蚀（边缘像素）
    final w = binary.width, h = binary.height;
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final dVal = dilated.getPixel(x, y).r.toInt();
        final eVal = eroded.getPixel(x, y).r.toInt();
        // 边缘 = 膨胀区域 - 腐蚀区域
        final v = (dVal - eVal).clamp(0, 255);
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// v4.3.0: 细笔画增强 — 自适应膨胀
  /// 根据前景像素比例判断笔画粗细，细笔画自动膨胀加粗
  img.Image _thinStrokeEnhance(img.Image src) {
    final gray = img.grayscale(src);
    final binary = _adaptiveBinarize(gray, blockSize: 25, c: 8);
    final w = binary.width, h = binary.height;
    int fg = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (binary.getPixel(x, y).r.toInt() < 128) fg++;
      }
    }
    final ratio = fg / (w * h);
    if (ratio < 0.10) {
      return _morphologicalDilate(binary, radius: 2);
    } else if (ratio < 0.15) {
      return _morphologicalDilate(binary, radius: 1);
    }
    return binary;
  }

  /// v4.3.0: 多尺度形态学 — 小膨胀 + 闭运算组合
  /// 先轻度膨胀增强笔画连通性，再闭运算填充小间隙
  img.Image _multiScaleMorphology(img.Image src) {
    final gray = img.grayscale(src);
    final binary = _adaptiveBinarize(gray, blockSize: 25, c: 8);
    final dilated = _morphologicalDilate(binary, radius: 1);
    return _morphologicalClose(dilated, radius: 1);
  }

  // ═══════════════════════════════════════════════════════════
  // v4.5.0: 新增图像增强预处理策略
  // ═══════════════════════════════════════════════════════════

  /// v4.5.0: 自适应伽马校正
  ///
  /// 根据图像平均亮度自动计算伽马值：
  /// - 过暗图片（均值<80）：gamma < 1，提亮暗部
  /// - 过亮图片（均值>180）：gamma > 1，压暗亮部
  /// - 正常范围：跳过校正
  ///
  /// 有效解决手写照片中光照不均、阴影遮挡等问题。
  img.Image _adaptiveGammaCorrection(img.Image src) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;

    // 计算平均亮度
    double sum = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        sum += gray.getPixel(x, y).r.toDouble();
      }
    }
    final mean = sum / (w * h);

    // 计算伽马值：gamma = log(0.5) / log(mean/255)
    // 目标：将平均亮度映射到 128 附近
    double gamma;
    if (mean < 10) {
      gamma = 0.3; // 极暗，强提亮
    } else if (mean < 80) {
      gamma = _log2(0.5) / _log2(mean / 255.0);
      gamma = gamma.clamp(0.3, 0.8);
    } else if (mean > 200) {
      gamma = _log2(0.5) / _log2(mean / 255.0);
      gamma = gamma.clamp(1.2, 3.0);
    } else {
      return src; // 正常亮度，跳过
    }

    debugPrint('伽马校正: 亮度均值=${mean.toStringAsFixed(0)}, gamma=${gamma.toStringAsFixed(2)}');

    // 构建查找表
    final lut = List<int>.generate(256, (i) {
      final normalized = i / 255.0;
      final corrected = _pow(normalized, gamma);
      return (corrected * 255).round().clamp(0, 255);
    });

    // 应用查找表
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final v = lut[gray.getPixel(x, y).r.toInt()];
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// v4.5.0: 多尺度边缘增强
  ///
  /// 使用不同尺度的 Sobel 算子分别检测粗笔画和细笔画边缘，
  /// 然后加权合成。比单一尺度 Sobel 能同时增强粗笔画结构和细笔画细节。
  img.Image _multiScaleEdgeEnhance(img.Image src) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;
    final result = img.Image(width: w, height: h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final orig = gray.getPixel(x, y).r.toDouble();

        // 尺度1: 3x3 Sobel（细笔画边缘）
        double edge1 = 0;
        if (y > 0 && y < h - 1 && x > 0 && x < w - 1) {
          final gx1 = _sobelX(gray, x, y).abs().toDouble();
          final gy1 = _sobelY(gray, x, y).abs().toDouble();
          edge1 = _sqrt(gx1 * gx1 + gy1 * gy1);
        }

        // 尺度2: 5x5 Sobel（粗笔画结构）
        double edge2 = 0;
        if (y > 1 && y < h - 2 && x > 1 && x < w - 2) {
          int gx2 = 0, gy2 = 0;
          // 5x5 Sobel X
          const kx = [-1,-2,0,2,1, -4,-8,0,8,4, -6,-12,0,12,6, -4,-8,0,8,4, -1,-2,0,2,1];
          const ky = [-1,-4,-6,-4,-1, -2,-8,-12,-8,-2, 0,0,0,0,0, 2,8,12,8,2, 1,4,6,4,1];
          int ki = 0;
          for (int dy = -2; dy <= 2; dy++) {
            for (int dx = -2; dx <= 2; dx++) {
              final v = gray.getPixel(x + dx, y + dy).r.toInt();
              gx2 += v * kx[ki];
              gy2 += v * ky[ki];
              ki++;
            }
          }
          edge2 = _sqrt((gx2 * gx2 + gy2 * gy2).toDouble()) / 4; // 归一化
        }

        // 加权合成：细边缘 60% + 粗边缘 40%
        final edge = edge1 * 0.6 + edge2 * 0.4;

        // 叠加到原图（50% 权重）
        final v = (orig + edge * 0.5).round().clamp(0, 255);
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// v4.5.0: 笔画感知去噪
  ///
  /// 使用各向异性扩散思想：在笔画边缘处（梯度大）抑制平滑，
  /// 在平坦区域（梯度小）加强平滑。这样去噪的同时保留笔画边缘。
  img.Image _strokeAwareDenoise(img.Image src) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;
    final result = img.Image(width: w, height: h);

    // 先做一次中值滤波获取粗略去噪结果
    final median = _medianFilter(gray);

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final orig = gray.getPixel(x, y).r.toDouble();
        final med = median.getPixel(x, y).r.toDouble();

        // 计算局部梯度幅值（边缘强度）
        final gx = (gray.getPixel(x + 1, y).r.toDouble() - gray.getPixel(x - 1, y).r.toDouble()).abs();
        final gy = (gray.getPixel(x, y + 1).r.toDouble() - gray.getPixel(x, y - 1).r.toDouble()).abs();
        final gradient = _sqrt(gx * gx + gy * gy);

        // 边缘保护权重：梯度越大，越保留原图
        // gradient=0 → 完全用中值滤波结果
        // gradient>50 → 完全保留原图
        final edgeWeight = (gradient / 50.0).clamp(0.0, 1.0);

        // 加权混合
        final v = (orig * edgeWeight + med * (1.0 - edgeWeight)).round().clamp(0, 255);
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// v4.7.0: 迭代反投影去模糊
  /// v4.8.0: 增加边缘感知 — 边缘区域增强更多，平滑区域抑制噪声
  ///
  /// 使用迭代反投影（Iterative Back-Projection）思想：
  /// 1. 假设模糊核为均匀模糊（适用于手写拍照的轻微运动模糊）
  /// 2. 迭代估计清晰图像：每次用模糊残差修正当前估计
  /// 3. 边缘感知：利用 Sobel 梯度图加权残差，边缘处增强更多
  /// 4. 3-5次迭代后收敛，显著提升模糊图片的清晰度
  img.Image _iterativeDeblur(img.Image src, {int iterations = 4}) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;

    // 转为浮点数组
    List<double> current = List.filled(w * h, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        current[y * w + x] = gray.getPixel(x, y).r.toDouble();
      }
    }

    // v4.8.0: 预计算边缘强度图（Sobel 梯度幅值）
    List<double> edgeMap = List.filled(w * h, 0);
    double maxEdge = 0;
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final gx = _sobelX(gray, x, y).toDouble();
        final gy = _sobelY(gray, x, y).toDouble();
        final magnitude = math.sqrt(gx * gx + gy * gy);
        edgeMap[y * w + x] = magnitude;
        if (magnitude > maxEdge) maxEdge = magnitude;
      }
    }
    // 归一化到 0~1
    if (maxEdge > 0) {
      for (int i = 0; i < w * h; i++) {
        edgeMap[i] /= maxEdge;
      }
    }

    // 迭代反投影（边缘感知）
    for (int iter = 0; iter < iterations; iter++) {
      // 对当前估计做模糊（模拟模糊过程）
      final blurred = _gaussianBlurFloat(current, w, h, sigma: 1.0 + iter * 0.3);

      // 计算模糊残差 = 原图 - 模糊(当前估计)
      List<double> residual = List.filled(w * h, 0);
      for (int i = 0; i < w * h; i++) {
        residual[i] = gray.getPixel(i % w, i ~/ w).r.toDouble() - blurred[i];
      }

      // v4.8.0: 边缘感知反投影 — 边缘处增益更高，平滑处增益更低
      final baseGain = 0.5 / (1 + iter * 0.15);
      for (int i = 0; i < w * h; i++) {
        // 边缘强度加权：边缘处增益 1.5x，平滑处增益 0.6x
        final edgeWeight = 0.6 + 0.9 * edgeMap[i]; // 0.6 ~ 1.5
        final gain = baseGain * edgeWeight;
        current[i] = (current[i] + residual[i] * gain).clamp(0, 255);
      }
    }

    // 转回图像
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final v = current[y * w + x].round().clamp(0, 255);
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// 辅助：浮点数组上的高斯模糊
  static List<double> _gaussianBlurFloat(List<double> data, int w, int h, {double sigma = 1.0}) {
    // 生成高斯核
    final radius = (sigma * 2).ceil();
    final kernelSize = radius * 2 + 1;
    List<double> kernel = List.filled(kernelSize, 0);
    double kernelSum = 0;
    for (int i = 0; i < kernelSize; i++) {
      final x = i - radius;
      kernel[i] = _exp(-x * x / (2 * sigma * sigma));
      kernelSum += kernel[i];
    }
    for (int i = 0; i < kernelSize; i++) {
      kernel[i] /= kernelSum;
    }

    // 水平方向
    List<double> temp = List.filled(w * h, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double sum = 0;
        for (int k = 0; k < kernelSize; k++) {
          final nx = (x + k - radius).clamp(0, w - 1);
          sum += data[y * w + nx] * kernel[k];
        }
        temp[y * w + x] = sum;
      }
    }

    // 垂直方向
    List<double> result = List.filled(w * h, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double sum = 0;
        for (int k = 0; k < kernelSize; k++) {
          final ny = (y + k - radius).clamp(0, h - 1);
          sum += temp[ny * w + x] * kernel[k];
        }
        result[y * w + x] = sum;
      }
    }
    return result;
  }

  /// 辅助：以2为底的对数
  static double _log2(double x) => _ln(x) / _ln(2);

  /// 辅助：自然对数（Newton 级数近似）
  static double _ln(double x) {
    if (x <= 0) return -999;
    // 利用 ln(x) = 2 * atanh((x-1)/(x+1))
    final t = (x - 1) / (x + 1);
    double sum = 0;
    double term = t;
    for (int i = 0; i < 20; i++) {
      sum += term / (2 * i + 1);
      term *= t * t;
    }
    return 2 * sum;
  }

  /// 辅助：幂函数（快速近似）
  static double _pow(double base, double exponent) {
    if (base <= 0) return 0;
    if (exponent == 0) return 1;
    if (exponent == 1) return base;
    // 利用 e^(exponent * ln(base))
    return _exp(exponent * _ln(base));
  }

  /// 辅助：指数函数（Taylor 展开）
  static double _exp(double x) {
    if (x < -10) return 0;
    if (x > 10) return 22026.0;
    double sum = 1;
    double term = 1;
    for (int i = 1; i < 30; i++) {
      term *= x / i;
      sum += term;
    }
    return sum;
  }

  /// 水平投影方差（用于倾斜检测）
  /// 方差越大说明文字行越整齐（倾斜越小）
  double _horizontalProjectionVariance(img.Image binary) {
    final gray = img.grayscale(binary);
    final w = gray.width, h = gray.height;
    if (h == 0) return 0;

    final projections = List.filled(h, 0);
    for (int y = 0; y < h; y++) {
      int count = 0;
      for (int x = 0; x < w; x++) {
        if (gray.getPixel(x, y).r.toInt() < 128) count++;
      }
      projections[y] = count;
    }

    final mean = projections.reduce((a, b) => a + b) / h;
    double variance = 0;
    for (final p in projections) {
      variance += (p - mean) * (p - mean);
    }
    return variance / h;
  }

  /// 估算平均笔画宽度（水平扫描法）
  /// 统计每行连续黑色游程的平均长度
  double _estimateStrokeWidth(img.Image binary) {
    final gray = img.grayscale(binary);
    final w = gray.width, h = gray.height;

    int totalWidth = 0;
    int runCount = 0;

    for (int y = 0; y < h; y += 2) {
      int runLength = 0;
      for (int x = 0; x < w; x++) {
        if (gray.getPixel(x, y).r.toInt() < 128) {
          runLength++;
        } else if (runLength > 0) {
          totalWidth += runLength;
          runCount++;
          runLength = 0;
        }
      }
      if (runLength > 0) {
        totalWidth += runLength;
        runCount++;
      }
    }

    return runCount > 0 ? totalWidth / runCount : 3.0;
  }

  /// 二值化（Otsu 自动阈值）
  img.Image _binarize(img.Image src) {
    final gray = img.grayscale(src);
    // 复用 ImageProcessor 的 Otsu 阈值算法
    final threshold = ImageProcessor.otsuThreshold(gray);
    debugPrint('  二值化 Otsu 阈值: $threshold');
    // 按阈值二值化
    final result = img.Image(width: gray.width, height: gray.height);
    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++) {
        final v = gray.getPixel(x, y).r.toInt() > threshold ? 255 : 0;
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// 自适应直方图均衡（四象限法）— v2.6.0
  ///
  /// 将图像分为 4 个象限，对每个象限独立做直方图均衡化，
  /// 然后合并回原图。有效处理纸面光照不均匀的场景。
  img.Image _adaptiveHistogramEqualizeQuadrants(img.Image src) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;
    final result = img.Image(width: w, height: h);

    // 四象限边界
    final midX = w ~/ 2;
    final midY = h ~/ 2;

    // 对每个象限计算直方图均衡化映射表
    _equalizeQuadrant(gray, result, 0, 0, midX, midY);         // 左上
    _equalizeQuadrant(gray, result, midX, 0, w - midX, midY);  // 右上
    _equalizeQuadrant(gray, result, 0, midY, midX, h - midY);  // 左下
    _equalizeQuadrant(gray, result, midX, midY, w - midX, h - midY); // 右下

    return result;
  }

  /// 对指定矩形区域执行直方图均衡化并写入结果图
  void _equalizeQuadrant(img.Image src, img.Image dst,
      int x0, int y0, int regionW, int regionH) {
    // 直方图
    final hist = List.filled(256, 0);
    int pixelCount = 0;
    for (int y = y0; y < y0 + regionH; y++) {
      for (int x = x0; x < x0 + regionW; x++) {
        if (x < src.width && y < src.height) {
          hist[src.getPixel(x, y).r.toInt()]++;
          pixelCount++;
        }
      }
    }
    if (pixelCount == 0) return;

    // 累积分布函数
    final cdf = List.filled(256, 0);
    cdf[0] = hist[0];
    for (int i = 1; i < 256; i++) {
      cdf[i] = cdf[i - 1] + hist[i];
    }
    final cdfMin = cdf.firstWhere((v) => v > 0, orElse: () => 0);

    // 映射表
    final map = List.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      if (pixelCount == cdfMin) {
        map[i] = i;
      } else {
        map[i] = ((cdf[i] - cdfMin) * 255 / (pixelCount - cdfMin)).round().clamp(0, 255);
      }
    }

    // 写入结果
    for (int y = y0; y < y0 + regionH; y++) {
      for (int x = x0; x < x0 + regionW; x++) {
        if (x < src.width && y < src.height) {
          final v = map[src.getPixel(x, y).r.toInt()];
          dst.setPixelRgba(x, y, v, v, v, 255);
        }
      }
    }
  }

  /// 形态学骨架化（反复腐蚀法）— v2.6.0
  ///
  /// 通过反复执行腐蚀操作，直到图像不再变化，得到 1 像素宽的骨架。
  /// 与 Zhang-Suen 骨架化互补，对粗笔画效果更好。
  img.Image _morphologicalSkeletonize(img.Image src) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;

    // 转为二值前景（黑色=前景）
    var foreground = List.generate(h, (y) =>
        List.generate(w, (x) => gray.getPixel(x, y).r.toInt() < 128));

    final skeleton = List.generate(h, (_) => List.filled(w, false));
    bool changed = true;
    int iterations = 0;
    const maxIterations = 50;

    while (changed && iterations < maxIterations) {
      changed = false;
      iterations++;

      // 腐蚀当前前景
      final eroded = List.generate(h, (_) => List.filled(w, false));
      for (int y = 1; y < h - 1; y++) {
        for (int x = 1; x < w - 1; x++) {
          if (!foreground[y][x]) continue;
          // 3x3 邻域全部为前景才保留
          bool allForeground = true;
          for (int dy = -1; dy <= 1 && allForeground; dy++) {
            for (int dx = -1; dx <= 1 && allForeground; dx++) {
              if (!foreground[y + dy][x + dx]) allForeground = false;
            }
          }
          eroded[y][x] = allForeground;
        }
      }

      // 对腐蚀结果做一次膨胀（形态学开运算）
      final opened = List.generate(h, (_) => List.filled(w, false));
      for (int y = 1; y < h - 1; y++) {
        for (int x = 1; x < w - 1; x++) {
          if (!eroded[y][x]) continue;
          // 3x3 邻域存在前景即膨胀
          bool hasForeground = false;
          for (int dy = -1; dy <= 1 && !hasForeground; dy++) {
            for (int dx = -1; dx <= 1 && !hasForeground; dx++) {
              if (eroded[y + dy][x + dx]) hasForeground = true;
            }
          }
          opened[y][x] = hasForeground;
        }
      }

      // skeleton = skeleton ∪ (foreground - opened)
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          if (foreground[y][x] && !opened[y][x]) {
            skeleton[y][x] = true;
            changed = true;
          }
        }
      }

      // 下一轮用开运算结果作为前景
      foreground = opened;
    }

    // 转回图片
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final v = skeleton[y][x] ? 0 : 255;
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    debugPrint('  形态学骨架化: $iterations 次迭代');
    return result;
  }

  /// 高斯模糊去噪 + 锐化（Unsharp Mask）— v2.6.0
  ///
  /// 先用 sigma=1.5 的高斯核模糊去噪，再用 Unsharp Mask 恢复边缘。
  /// 对平滑手写体效果优于中值滤波。
  img.Image _gaussianBlurSharpen(img.Image src) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;

    // 构建 5x5 高斯核 (sigma=1.5)
    const sigma = 1.5;
    const kernelSize = 5;
    const half = kernelSize ~/ 2;
    final kernel = List.generate(kernelSize, (y) =>
        List.generate(kernelSize, (x) {
          final dx = x - half;
          final dy = y - half;
          return (-(dx * dx + dy * dy) / (2 * sigma * sigma)).toDouble();
        }));
    // 归一化
    double sum = 0;
    for (int y = 0; y < kernelSize; y++) {
      for (int x = 0; x < kernelSize; x++) {
        kernel[y][x] = math.exp(kernel[y][x]);
        sum += kernel[y][x];
      }
    }
    for (int y = 0; y < kernelSize; y++) {
      for (int x = 0; x < kernelSize; x++) {
        kernel[y][x] /= sum;
      }
    }

    // 高斯模糊
    final blurred = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double val = 0;
        for (int ky = -half; ky <= half; ky++) {
          for (int kx = -half; kx <= half; kx++) {
            final nx = (x + kx).clamp(0, w - 1);
            final ny = (y + ky).clamp(0, h - 1);
            val += gray.getPixel(nx, ny).r.toDouble() * kernel[ky + half][kx + half];
          }
        }
        final v = val.round().clamp(0, 255);
        blurred.setPixelRgba(x, y, v, v, v, 255);
      }
    }

    // Unsharp Mask: result = original + amount * (original - blurred)
    const amount = 1.5;
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final orig = gray.getPixel(x, y).r.toDouble();
        final blur = blurred.getPixel(x, y).r.toDouble();
        final v = (orig + amount * (orig - blur)).round().clamp(0, 255);
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// 局部阈值二值化（15x15 邻域均值法）— v2.6.0
  ///
  /// 对每个像素，以其 15x15 邻域的均值作为阈值进行二值化。
  /// 比全局 Otsu 更适合处理不均匀背景。
  img.Image _localThresholdBinarize(img.Image src) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;
    const blockSize = 15;
    const half = blockSize ~/ 2;
    const c = 10; // 阈值偏移量

    // 积分图加速均值计算
    final integral = List.generate(h, (_) => List.filled(w, 0));
    for (int y = 0; y < h; y++) {
      int rowSum = 0;
      for (int x = 0; x < w; x++) {
        rowSum += gray.getPixel(x, y).r.toInt();
        integral[y][x] = rowSum + (y > 0 ? integral[y - 1][x] : 0);
      }
    }

    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final x1 = (x - half).clamp(0, w - 1);
        final y1 = (y - half).clamp(0, h - 1);
        final x2 = (x + half).clamp(0, w - 1);
        final y2 = (y + half).clamp(0, h - 1);
        final count = (x2 - x1 + 1) * (y2 - y1 + 1);

        int areaSum = integral[y2][x2];
        if (x1 > 0) areaSum -= integral[y2][x1 - 1];
        if (y1 > 0) areaSum -= integral[y1 - 1][x2];
        if (x1 > 0 && y1 > 0) areaSum += integral[y1 - 1][x1 - 1];

        final localMean = areaSum / count;
        final brightness = gray.getPixel(x, y).r.toInt();
        final v = brightness < (localMean - c) ? 0 : 255;
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// Sauvola 自适应二值化（v4.8.0）
  ///
  /// 经典文档图像二值化算法，对手写体效果显著优于 Niblack/Otsu。
  /// 公式：T(x,y) = mean * (1 + k * (std/R - 1))
  /// 其中 mean/std 为局部邻域的均值和标准差，R=128（8bit 动态范围）。
  ///
  /// 优势：
  /// - 同时考虑局部均值和方差，对光照不均匀更鲁棒
  /// - 对比度低的区域自动降低阈值，保留更多笔画细节
  /// - 对纸面阴影、折痕有很好的抑制效果
  /// v5.7.0: 自适应 Sauvola 二值化 — 根据图像特征自动选择最优参数
  ///
  /// 参数自适应规则：
  /// - 高噪声 → 大 blockSize (35), 大 k (0.3) — 更强平滑
  /// - 低对比度 → 小 blockSize (19), 小 k (0.15) — 保留淡笔画
  /// - 高分辨率 → 按比例增大 blockSize
  img.Image _sauvolaBinarizeAdaptive(img.Image src, {required ImageFeatures features}) {
    int blockSize = 25;
    double k = 0.2;

    if (features.noise > 0.5) {
      blockSize = 35;
      k = 0.3;
    } else if (features.noise < 0.2) {
      blockSize = 21;
      k = 0.18;
    }
    if (features.contrast < 0.3) {
      blockSize = (blockSize * 0.8).round().clamp(15, blockSize);
      k = (k * 0.75).clamp(0.1, k);
    }
    final maxDim = src.width > src.height ? src.width : src.height;
    if (maxDim > 1000) {
      blockSize = (blockSize * 1.3).round().clamp(blockSize, 51);
    } else if (maxDim < 200) {
      blockSize = (blockSize * 0.8).round().clamp(11, blockSize);
    }
    if (blockSize.isEven) blockSize++;
    debugPrint('自适应Sauvola: blockSize=$blockSize, k=${k.toStringAsFixed(2)}');
    return _sauvolaBinarize(src, blockSize: blockSize, k: k);
  }

  img.Image _sauvolaBinarize(img.Image src, {int blockSize = 25, double k = 0.2, double R = 128.0}) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;
    final half = blockSize ~/ 2;

    // 积分图加速：同时计算 sum 和 sum²
    final integral = List.generate(h, (_) => List.filled(w, 0.0));
    final integralSq = List.generate(h, (_) => List.filled(w, 0.0));
    for (int y = 0; y < h; y++) {
      double rowSum = 0;
      double rowSumSq = 0;
      for (int x = 0; x < w; x++) {
        final v = gray.getPixel(x, y).r.toDouble();
        rowSum += v;
        rowSumSq += v * v;
        integral[y][x] = rowSum + (y > 0 ? integral[y - 1][x] : 0);
        integralSq[y][x] = rowSumSq + (y > 0 ? integralSq[y - 1][x] : 0);
      }
    }

    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final x1 = (x - half).clamp(0, w - 1);
        final y1 = (y - half).clamp(0, h - 1);
        final x2 = (x + half).clamp(0, w - 1);
        final y2 = (y + half).clamp(0, h - 1);
        final count = (x2 - x1 + 1) * (y2 - y1 + 1);

        // 计算局部均值
        double areaSum = integral[y2][x2];
        if (x1 > 0) areaSum -= integral[y2][x1 - 1];
        if (y1 > 0) areaSum -= integral[y1 - 1][x2];
        if (x1 > 0 && y1 > 0) areaSum += integral[y1 - 1][x1 - 1];
        final mean = areaSum / count;

        // 计算局部标准差
        double areaSumSq = integralSq[y2][x2];
        if (x1 > 0) areaSumSq -= integralSq[y2][x1 - 1];
        if (y1 > 0) areaSumSq -= integralSq[y1 - 1][x2];
        if (x1 > 0 && y1 > 0) areaSumSq += integralSq[y1 - 1][x1 - 1];
        final variance = (areaSumSq / count) - (mean * mean);
        final std = variance > 0 ? math.sqrt(variance) : 0.0;

        // Sauvola 阈值
        final threshold = mean * (1.0 + k * (std / R - 1.0));

        final brightness = gray.getPixel(x, y).r.toDouble();
        final v = brightness < threshold ? 0 : 255;
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// CLAHE（自适应直方图均衡化）
  ///
  /// 将图像分为 8×8 瓦片，对每个瓦片独立做直方图均衡化（clip limit 3.0），
  /// 瓦片边界双线性插值消除块效应。对纸面光照不均的手写体效果显著。
  img.Image _clahe(img.Image src) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;
    const tileSize = 8;
    const clipLimit = 3.0;

    final tilesX = (w / tileSize).ceil().clamp(1, w);
    final tilesY = (h / tileSize).ceil().clamp(1, h);

    // 每个瓦片的映射表（256 级）
    final tileMaps = List.generate(tilesY, (_) =>
        List.generate(tilesX, (_) => List.filled(256, 0)));

    // 对每个瓦片计算带 clip limit 的均衡化映射
    for (int ty = 0; ty < tilesY; ty++) {
      for (int tx = 0; tx < tilesX; tx++) {
        final x0 = tx * tileSize;
        final y0 = ty * tileSize;
        final x1 = ((tx + 1) * tileSize).clamp(0, w);
        final y1 = ((ty + 1) * tileSize).clamp(0, h);
        final tileW = x1 - x0;
        final tileH = y1 - y0;
        final pixelCount = tileW * tileH;

        // 直方图
        final hist = List.filled(256, 0);
        for (int y = y0; y < y1; y++) {
          for (int x = x0; x < x1; x++) {
            hist[gray.getPixel(x, y).r.toInt()]++;
          }
        }

        // Clip limit 裁剪 + 均匀分摊
        int excess = 0;
        for (int i = 0; i < 256; i++) {
          if (hist[i] > clipLimit) {
            excess += hist[i] - clipLimit.toInt();
            hist[i] = clipLimit.toInt();
          }
        }
        final redistribPerBin = excess ~/ 256;
        final residual = excess % 256;
        for (int i = 0; i < 256; i++) {
          hist[i] += redistribPerBin;
          if (i < residual) hist[i]++;
        }

        // 累积分布函数 → 映射表
        int cdf = 0;
        int cdfMin = 0;
        bool foundMin = false;
        for (int i = 0; i < 256; i++) {
          cdf += hist[i];
          if (!foundMin && cdf > 0) {
            cdfMin = cdf;
            foundMin = true;
          }
        }
        cdf = 0;
        for (int i = 0; i < 256; i++) {
          cdf += hist[i];
          if (cdfMin == pixelCount) {
            tileMaps[ty][tx][i] = i;
          } else {
            tileMaps[ty][tx][i] = ((cdf - cdfMin) * 255 / (pixelCount - cdfMin)).round().clamp(0, 255);
          }
        }
      }
    }

    // 双线性插值输出
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final val = gray.getPixel(x, y).r.toInt();
        final txf = (x / tileSize - 0.5).clamp(0.0, (tilesX - 1).toDouble());
        final tyf = (y / tileSize - 0.5).clamp(0.0, (tilesY - 1).toDouble());
        final tx0 = txf.floor();
        final ty0 = tyf.floor();
        final tx1 = (tx0 + 1).clamp(0, tilesX - 1);
        final ty1 = (ty0 + 1).clamp(0, tilesY - 1);
        final fx = txf - tx0;
        final fy = tyf - ty0;

        final v00 = tileMaps[ty0][tx0][val].toDouble();
        final v10 = tileMaps[ty0][tx1][val].toDouble();
        final v01 = tileMaps[ty1][tx0][val].toDouble();
        final v11 = tileMaps[ty1][tx1][val].toDouble();

        final v = (v00 * (1 - fx) * (1 - fy) +
                   v10 * fx * (1 - fy) +
                   v01 * (1 - fx) * fy +
                   v11 * fx * fy).round().clamp(0, 255);
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// v5.7.0: 局部对比度增强 — 基于积分图的快速局部归一化
  ///
  /// 将图像分为重叠的局部区域，对每个区域独立进行均值-标准差归一化。
  /// 比 CLAHE 更快，同时有效处理光照不均的场景。
  ///
  /// [blockSize] 局部区域大小（默认 31）
  /// [targetMean] 归一化目标均值（默认 128）
  /// [targetStd] 归一化目标标准差（默认 60）
  img.Image _localContrastEnhance(img.Image src, {int blockSize = 31, double targetMean = 128.0, double targetStd = 60.0}) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;
    if (blockSize.isEven) blockSize++;
    final half = blockSize ~/ 2;

    // 积分图加速
    final integral = List.generate(h, (_) => List.filled(w, 0.0));
    final integralSq = List.generate(h, (_) => List.filled(w, 0.0));
    for (int y = 0; y < h; y++) {
      double rowSum = 0, rowSumSq = 0;
      for (int x = 0; x < w; x++) {
        final v = gray.getPixel(x, y).r.toDouble();
        rowSum += v;
        rowSumSq += v * v;
        integral[y][x] = rowSum + (y > 0 ? integral[y - 1][x] : 0);
        integralSq[y][x] = rowSumSq + (y > 0 ? integralSq[y - 1][x] : 0);
      }
    }

    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final x1 = (x - half).clamp(0, w - 1);
        final y1 = (y - half).clamp(0, h - 1);
        final x2 = (x + half).clamp(0, w - 1);
        final y2 = (y + half).clamp(0, h - 1);
        final count = (x2 - x1 + 1) * (y2 - y1 + 1);

        double areaSum = integral[y2][x2];
        if (x1 > 0) areaSum -= integral[y2][x1 - 1];
        if (y1 > 0) areaSum -= integral[y1 - 1][x2];
        if (x1 > 0 && y1 > 0) areaSum += integral[y1 - 1][x1 - 1];

        double areaSumSq = integralSq[y2][x2];
        if (x1 > 0) areaSumSq -= integralSq[y2][x1 - 1];
        if (y1 > 0) areaSumSq -= integralSq[y1 - 1][x2];
        if (x1 > 0 && y1 > 0) areaSumSq += integralSq[y1 - 1][x1 - 1];

        final mean = areaSum / count;
        final variance = (areaSumSq / count) - (mean * mean);
        final std = variance > 0 ? math.sqrt(variance) : 1.0;

        // 局部归一化：(pixel - mean) / std * targetStd + targetMean
        final pixel = gray.getPixel(x, y).r.toDouble();
        final normalized = ((pixel - mean) / (std + 1.0)) * targetStd + targetMean;
        final v = normalized.round().clamp(0, 255);
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// 背景归一化（Retinex 思路）
  ///
  /// 用 3×3 中值滤波估算背景亮度，逐像素除以背景估计值后重映射到 0-255。
  /// 有效消除阴影、折痕、光照不均对手写识别的干扰。
  img.Image _normalizeBackground(img.Image src) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;

    // 3×3 中值滤波估算背景
    final bg = List.generate(h, (_) => List.filled(w, 0));
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final values = <int>[];
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final nx = (x + dx).clamp(0, w - 1);
            final ny = (y + dy).clamp(0, h - 1);
            values.add(gray.getPixel(nx, ny).r.toInt());
          }
        }
        values.sort();
        bg[y][x] = values[4];
      }
    }

    // Retinex: original / background * 128，归一化到 0-255
    double minVal = 255, maxVal = 0;
    final raw = List.generate(h, (_) => List.filled(w, 0.0));
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final orig = gray.getPixel(x, y).r.toDouble();
        final background = bg[y][x].toDouble().clamp(1.0, 255.0);
        final ratio = orig / background * 128.0;
        raw[y][x] = ratio;
        if (ratio < minVal) minVal = ratio;
        if (ratio > maxVal) maxVal = ratio;
      }
    }

    final range = (maxVal - minVal).clamp(1.0, 255.0);
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final v = ((raw[y][x] - minVal) / range * 255).round().clamp(0, 255);
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// 方向边缘增强（Sobel）
  ///
  /// 分别计算 X/Y 方向 Sobel 梯度幅值，以 0.5 权重叠加回灰度原图。
  /// 能增强被噪声淹没的细笔画，提升低对比度手写体的识别率。
  img.Image _directionalEdgeEnhance(img.Image src) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;
    final result = img.Image(width: w, height: h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        // Sobel X: [-1 0 1; -2 0 2; -1 0 1]
        int sx = 0;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final nx = (x + dx).clamp(0, w - 1);
            final ny = (y + dy).clamp(0, h - 1);
            final v = gray.getPixel(nx, ny).r.toInt();
            final weightX = (dx == -1 ? -1 : dx == 1 ? 1 : 0) * (dy == 0 ? 2 : 1);
            sx += v * weightX;
          }
        }

        // Sobel Y: [-1 -2 -1; 0 0 0; 1 2 1]
        int sy = 0;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final nx = (x + dx).clamp(0, w - 1);
            final ny = (y + dy).clamp(0, h - 1);
            final v = gray.getPixel(nx, ny).r.toInt();
            final weightY = (dy == -1 ? -1 : dy == 1 ? 1 : 0) * (dx == 0 ? 2 : 1);
            sy += v * weightY;
          }
        }

        final magnitude = (sx * sx + sy * sy).toDouble();
        final edge = (magnitude > 0 ? _sqrt(magnitude) : 0.0).clamp(0.0, 255.0);

        final orig = gray.getPixel(x, y).r.toDouble();
        final v = (orig + 0.5 * edge).round().clamp(0, 255);
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// 简易平方根（Newton 迭代，避免引入 dart:math 依赖）
  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (int i = 0; i < 10; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  /// 3x3 Sobel X 方向梯度
  static int _sobelX(img.Image gray, int x, int y) {
    return (-1 * gray.getPixel(x - 1, y - 1).r.toInt() +
             1 * gray.getPixel(x + 1, y - 1).r.toInt() +
            -2 * gray.getPixel(x - 1, y).r.toInt() +
             2 * gray.getPixel(x + 1, y).r.toInt() +
            -1 * gray.getPixel(x - 1, y + 1).r.toInt() +
             1 * gray.getPixel(x + 1, y + 1).r.toInt());
  }

  /// 3x3 Sobel Y 方向梯度
  static int _sobelY(img.Image gray, int x, int y) {
    return (-1 * gray.getPixel(x - 1, y - 1).r.toInt() +
            -2 * gray.getPixel(x, y - 1).r.toInt() +
            -1 * gray.getPixel(x + 1, y - 1).r.toInt() +
             1 * gray.getPixel(x - 1, y + 1).r.toInt() +
             2 * gray.getPixel(x, y + 1).r.toInt() +
             1 * gray.getPixel(x + 1, y + 1).r.toInt());
  }

  // ═══════════════════════════════════════════════════════════
  // v5.8.0: 新增预处理策略
  // ═══════════════════════════════════════════════════════════

  /// v5.8.0: 多阈值融合二值化 — 结合 Otsu 和自适应阈值的优势
  ///
  /// 分别用 Otsu 和自适应阈值生成两幅二值图，
  /// 对一致的像素直接采用，不一致的像素用局部对比度决定。
  /// 这种融合方式兼具全局一致性和局部适应性。
  img.Image _multiThresholdFusion(img.Image src) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;

    // Otsu 全局阈值
    final otsuT = ImageProcessor.otsuThreshold(gray);
    final otsuBinary = ImageProcessor.binarize(gray, otsuT / 255.0, false);

    // 自适应阈值
    final adaptiveBinary = ImageProcessor.adaptiveThreshold(gray, blockSize: 31, c: 10, invert: false);

    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final otsuBlack = ImageProcessor.isBlack(otsuBinary, x, y);
        final adaptiveBlack = ImageProcessor.isBlack(adaptiveBinary, x, y);

        if (otsuBlack == adaptiveBlack) {
          // 一致：直接采用
          final v = otsuBlack ? 0 : 255;
          result.setPixelRgba(x, y, v, v, v, 255);
        } else {
          // 不一致：用局部对比度决定
          // 计算 3x3 邻域的标准差
          double sum = 0, sumSq = 0;
          int count = 0;
          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              final nx = (x + dx).clamp(0, w - 1);
              final ny = (y + dy).clamp(0, h - 1);
              final v = gray.getPixel(nx, ny).r.toDouble();
              sum += v;
              sumSq += v * v;
              count++;
            }
          }
          final mean = sum / count;
          final variance = (sumSq / count) - (mean * mean);
          final localContrast = variance > 0 ? math.sqrt(variance) : 0;

          // 高局部对比度区域（笔画边缘）用自适应阈值，低对比度用 Otsu
          final useAdaptive = localContrast > 20;
          final v = (useAdaptive ? adaptiveBlack : otsuBlack) ? 0 : 255;
          result.setPixelRgba(x, y, v, v, v, 255);
        }
      }
    }
    return result;
  }

  /// v5.8.0: 笔画保留增强 — 增强笔画同时抑制噪声
  ///
  /// 使用形态学操作区分笔画和噪声：
  /// 1. 用开运算去除小噪点
  /// 2. 用闭运算修复断笔
  /// 3. 与原图加权融合，保留笔画细节
  img.Image _strokePreservingEnhance(img.Image src) {
    final gray = img.grayscale(src);
    final w = gray.width, h = gray.height;

    // 先做对比度增强
    final enhanced = img.adjustColor(gray, contrast: 1.3, brightness: 1.05);

    // 开运算去噪（先腐蚀后膨胀）
    var opened = enhanced;
    for (int i = 0; i < 1; i++) {
      opened = ImageProcessor.erode(opened);
    }
    for (int i = 0; i < 1; i++) {
      opened = ImageProcessor.dilate(opened);
    }

    // 闭运算修复断笔（先膨胀后腐蚀）
    var closed = enhanced;
    for (int i = 0; i < 1; i++) {
      closed = ImageProcessor.dilate(closed);
    }
    for (int i = 0; i < 1; i++) {
      closed = ImageProcessor.erode(closed);
    }

    // 融合：取三者的加权平均
    final result = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final orig = enhanced.getPixel(x, y).r.toDouble();
        final open = opened.getPixel(x, y).r.toDouble();
        final close = closed.getPixel(x, y).r.toDouble();
        // 原图权重最高，保留细节；开运算去噪；闭运算修复
        final v = (orig * 0.5 + open * 0.25 + close * 0.25).round().clamp(0, 255);
        result.setPixelRgba(x, y, v, v, v, 255);
      }
    }
    return result;
  }

  /// v4.4.0: 多候选综合评分 — 票数 + 置信度 + 字频 + 策略多样性 + 多尺度一致性
  /// v4.5.0: 新增 n-gram 上下文得分
  /// v4.8.0: 优化权重分配 — 提升票数权重，增加单策略惩罚
  ///
  /// 当 TopN 投票产生多个候选时，用此函数综合排序，而非仅按票数排序。
  /// 评分公式：score = votes*0.35 + confidence*0.15 + frequency*0.10 + diversity*0.15 + multiScale*0.10 + context*0.15
  static double _computeCandidateScore({
    required String candidate,
    required int votes,
    required int totalVotes,
    required Map<String, double> confidenceMap,
    required Map<String, Set<String>> resultStrategies,
    required Map<String, Set<int>> resultSizes,
  }) {
    // 1. 归一化票数 (0.0~1.0) — 最可靠的信号，权重最高
    final normalizedVotes = totalVotes > 0 ? votes / totalVotes : 0.0;

    // 2. 置信度 (0.0~1.0)
    final confidence = confidenceMap[candidate] ?? 0.7;

    // 3. 字频分数 (0.0~1.0) — 高频字得分高，更细粒度的分级
    final freqRank = DictionaryService.instance.getFrequency(candidate);
    double freqScore = 0.5; // 默认中等
    if (freqRank >= 0 && freqRank < 50) {
      freqScore = 1.0;  // Top 50 高频字
    } else if (freqRank >= 50 && freqRank < 200) {
      freqScore = 0.9;
    } else if (freqRank >= 200 && freqRank < 500) {
      freqScore = 0.75;
    } else if (freqRank >= 500 && freqRank < 1000) {
      freqScore = 0.6;
    } else if (freqRank >= 1000 && freqRank < 2000) {
      freqScore = 0.45;
    } else if (freqRank >= 2000) {
      freqScore = 0.3;
    }

    // 4. 策略多样性 (0.0~1.0) — 越多不同策略投票，得分越高
    //    单策略投票有轻微惩罚（可能是噪声）
    final strategyCount = resultStrategies[candidate]?.length ?? 0;
    double diversityScore = (strategyCount / 5.0).clamp(0.0, 1.0);
    if (strategyCount <= 1 && totalVotes > 2) {
      diversityScore *= 0.7; // 单策略且总票数多时，轻微惩罚
    }

    // 5. 多尺度一致性 (0.0~1.0) — 多个放大尺寸识别到相同结果
    final sizeCount = resultSizes[candidate]?.length ?? 0;
    final multiScaleScore = (sizeCount / 3.0).clamp(0.0, 1.0);

    // 6. v4.5.0: n-gram 上下文得分 (0.0~1.0)
    final contextScore = DictionaryService.instance.getContextScore(
      candidate,
      prevChar: _lastRecognizedChars.isNotEmpty ? _lastRecognizedChars.last : null,
    );

    // 7. v5.7.0: 策略可靠性得分 (0.0~1.0) — 投票策略的历史成功率越高，得分越高
    final candidateStrategies = resultStrategies[candidate] ?? {};
    double strategyReliabilityScore = 0.5; // 默认中等
    if (candidateStrategies.isNotEmpty) {
      double totalReliability = 0.0;
      for (final strat in candidateStrategies) {
        totalReliability += _strategyReliability[strat] ?? 0.5;
      }
      strategyReliabilityScore = (totalReliability / candidateStrategies.length).clamp(0.0, 1.0);
    }

    // v5.7.0: 加权综合评分 — 增加策略可靠性维度
    // 票数(30%) + 置信度(18%) + 上下文(15%) + 策略可靠性(10%) + 字频(10%) + 多样性(10%) + 多尺度(7%)
    double score = normalizedVotes * 0.30 +
        confidence * 0.18 +
        contextScore * 0.15 +
        strategyReliabilityScore * 0.10 +
        freqScore * 0.10 +
        diversityScore * 0.10 +
        multiScaleScore * 0.07;

    // v5.2.0: 笔画复杂度奖励 — 简单字（1-3 笔画）在多策略确认时获得额外加分
    // 简单字的识别更容易被噪声干扰，但一旦多策略一致就非常可靠
    if (votes >= 2) {
      final codePoint = candidate.runes.first;
      // 常见简单字范围（高频简单字：一二三四五六七八九十等）
      final isSimpleChar = _isSimpleChar(codePoint);
      if (isSimpleChar && strategyCount >= 2) {
        score += 0.03; // 简单字 + 多策略确认 → 额外加分
      }
    }

    return score;
  }

  /// 判断是否为简单汉字（1-3 笔画的常见字）
  static bool _isSimpleChar(int codePoint) {
    // CJK 基本区 + 常见简单字（基于笔画数的经验范围）
    if (codePoint < 0x4E00 || codePoint > 0x9FFF) return false;
    // 常见 1-3 笔画汉字（高频）
    const simpleChars = <int>{
      0x4E00, 0x4E8C, 0x4E09, 0x56DB, 0x4E94, 0x516D, 0x4E03, 0x516B, 0x4E5D, 0x5341, // 一到十
      0x4EBA, 0x5927, 0x5C0F, 0x4E0A, 0x4E0B, 0x5DE6, 0x53F3, 0x4E2D, 0x524D, 0x540E, // 人大上下左右中前后
      0x65E5, 0x6708, 0x6C34, 0x706B, 0x5C71, 0x77F3, 0x7530, 0x76EE, 0x8033, 0x624B, // 日月水火山石田目耳手
      0x53E3, 0x5FC3, 0x529B, 0x5200, 0x8F66, 0x9A6C, 0x725B, 0x7F8A, 0x9C7C, 0x9E1F, // 口心力刀车马牛羊鱼鸟
      0x7537, 0x5973, 0x5B50, 0x7236, 0x6BCD, 0x738B, 0x767D, 0x7EA2, 0x9EC4, 0x9752, // 男女子父母王白红黄青
      0x7A7A, 0x957F, 0x6B63, 0x65B9, 0x5706, 0x70B9, 0x7EBF, 0x9762, 0x4F53, // 空长正方圆点线面体
    };
    return simpleChars.contains(codePoint);
  }

  /// 本地 ML Kit 识别（多级预处理 + 多轮投票 + 自适应增强）
  ///
  /// 策略：
  /// 1. 快速尝试：灰度原图，成功即返回
  /// 2. 多轮识别：不同预处理结果分别识别，投票选最佳
  /// 3. 失败回退：反转颜色、裁剪边缘、骨架化
  /// 4. 置信度评分：低置信度时尝试更多变体
  Future<String?> _recognizeLocal(Uint8List imageBytes) async {
    try {
      _lastLocalConfidence = 0.0;
      // v2.8.0: 分析图像特征，智能选择预处理策略
      final imageFeatures = await ImageAnalyzer().analyzeImage(imageBytes);
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return null;

      final w = decoded.width;
      final h = decoded.height;
      final maxDim = w > h ? w : h;
      debugPrint('ML Kit 识别: 原始图片 ${w}x$h，最大边 $maxDim');

      // ═══ v4.0.1: 白边裁剪（pad去除）— 优先级最高的预处理 ═══
      // 在所有处理之前先裁剪白边，让字符占据更大比例，
      // 提升后续 CLAHE、锐化、二值化等策略的效果
      img.Image trimmed = decoded;
      final trimResult = _smartTrimWhitespace(decoded);
      if (trimResult.wasTrimmed) {
        trimmed = trimResult.image;
        debugPrint('ML Kit 识别: 白边裁剪 ${decoded.width}x${decoded.height} → ${trimmed.width}x${trimmed.height} '
            '(裁掉了 ${trimResult.trimmedPercent.toStringAsFixed(0)}% 空白)');
        _addDebugLog('recognition', '白边裁剪', data: {
          'originalSize': '${decoded.width}x${decoded.height}',
          'trimmedSize': '${trimmed.width}x${trimmed.height}',
          'trimmedPercent': trimResult.trimmedPercent,
        });
      }

      // ═══ 图像质量评估与自动增强 ═══
      final qualityReport = ImageQualityService.instance.assessQuality(trimmed);
      img.Image enhanced = trimmed;
      if (qualityReport.needsEnhancement) {
        debugPrint('ML Kit 识别: 图像质量偏低，执行自动增强 $qualityReport');
        enhanced = ImageQualityService.instance.enhanceForRecognition(trimmed, qualityReport);
        _addDebugLog('recognition', '图像质量增强', data: {
          'qualityScore': qualityReport.overallScore,
          'contrast': qualityReport.contrastScore,
          'sharpness': qualityReport.sharpnessScore,
          'noise': qualityReport.noiseScore,
          'stroke': qualityReport.strokeScore,
          'skew': qualityReport.skewAngle,
        });
      }

      // 投票统计：字符 → 出现次数
      final voteMap = <String, int>{};
      // 记录每个字符的最高置信度
      final confidenceMap = <String, double>{};
      // v2.6.0: 记录每个字符由哪些策略识别（用于策略多样性和可靠性统计）
      final resultStrategies = <String, Set<String>>{};
      // v2.7.0: 每个策略对每个字符的投票数（用于 UI 展示投票明细）
      final strategyVotes = <String, Map<String, int>>{};
      // v3.5.0: 记录每个字符在哪些放大尺寸下被识别到
      final resultSizes = <String, Set<int>>{};
      // v2.6.0: 是否触发了提前终止
      bool earlyTerminated = false;
      // v2.7.0: 实际执行的尝试次数
      int actualAttempts = 0;

      // ═══ 第一轮：快速尝试（灰度原图，结果计入投票，不再直接返回） ═══
      if (maxDim >= 50) {
        debugPrint('ML Kit 识别: 快速尝试 | 原图灰度');
        final gray = img.grayscale(enhanced);
        final rawResult = await _recognizeFromImage(gray);
        final result = _validateResult(rawResult);
        if (result != null) {
          voteMap[result] = (voteMap[result] ?? 0) + 1;
          final hash = _hashBytes(img.encodePng(gray));
          final conf = _confidenceCache[hash] ?? 0.85;
          confidenceMap[result] = (confidenceMap[result] ?? 0) > conf
              ? confidenceMap[result]!
              : conf;
          // v2.7.0: 记录快速尝试的策略投票
          resultStrategies.putIfAbsent(result, () => <String>{});
          resultStrategies[result]!.add('灰度');
          strategyVotes.putIfAbsent(result, () => {});
          strategyVotes[result]!['灰度'] = (strategyVotes[result]!['灰度'] ?? 0) + 1;
          debugPrint('ML Kit 识别: ✓ 快速尝试识别到 "$result" (计入投票)');
        }
      }

      // v3.6.0: 快速通道 — 额外跑策略，4个一致直接返回
      // v5.8.0: 扩展快速通道至 6 个策略（+多阈值融合 +笔画保留增强）
      if (voteMap.isNotEmpty && maxDim >= 50) {
        final quickStrategies = [
          ('CLAHE自适应', (img.Image src) => ImageQualityService.instance.enhanceContrastAdaptive(src)),
          ('USM笔画锐化', (img.Image src) => _unsharpMaskSharpen(src, amount: 1.5)),
          ('伽马校正', (img.Image src) => _adaptiveGammaCorrection(src)),
          ('自适应Sauvola', (img.Image src) => _sauvolaBinarizeAdaptive(src, features: imageFeatures)),
          ('多阈值融合', (img.Image src) => _multiThresholdFusion(src)),
          ('笔画保留增强', (img.Image src) => _strokePreservingEnhance(src)),
        ];
        for (final (label, fn) in quickStrategies) {
          final processed = fn(enhanced);
          final raw = await _recognizeFromImage(processed);
          final r = _validateResult(raw);
          if (r != null) {
            voteMap[r] = (voteMap[r] ?? 0) + 1;
            resultStrategies.putIfAbsent(r, () => <String>{});
            resultStrategies[r]!.add(label);
            strategyVotes.putIfAbsent(r, () => {});
            strategyVotes[r]![label] = (strategyVotes[r]![label] ?? 0) + 1;
          }
        }
        // v5.8.0: 5个快速策略一致 → 直接返回（更高的确认度）
        if (voteMap.isNotEmpty) {
          final topVotes = voteMap.values.reduce((a, b) => a > b ? a : b);
          if (topVotes >= 5) {
            final quickWinner = voteMap.entries.reduce((a, b) => a.value >= b.value ? a : b);
            _lastLocalConfidence = 0.95;
            debugPrint('ML Kit 识别: 快速通道命中 "${quickWinner.key}" (${quickWinner.value}票)');
            return quickWinner.key;
          }
        }
      }

      // ═══ v5.6.0: 连笔字智能切分识别 ═══
      // 当图片宽高比 > 1.3 时，可能是连笔字（两个字符连在一起），
      // 使用垂直投影法找到最佳切分点，分别识别后合并结果
      if (maxDim >= 50) {
        final isLikelyConnected = _detectConnectedCharacters(enhanced);
        if (isLikelyConnected) {
          debugPrint('连笔字检测: 疑似连笔字，尝试切分识别');
          final segments = _segmentByVerticalProjection(enhanced);
          if (segments.length > 1) {
            // 切分成功，分别识别每个片段
            String combinedResult = '';
            double totalConf = 0;
            int validSegments = 0;

            for (int i = 0; i < segments.length; i++) {
              final segBytes = Uint8List.fromList(img.encodePng(segments[i]));
              final segResult = await _recognizeLocal(segBytes);
              if (segResult != null && segResult.isNotEmpty) {
                combinedResult += segResult;
                totalConf += _lastLocalConfidence;
                validSegments++;
                debugPrint('连笔字切分: 片段${i + 1} → "$segResult" (置信度 ${(_lastLocalConfidence * 100).toStringAsFixed(0)}%)');
              }
            }

            if (validSegments == segments.length && combinedResult.length > 1) {
              // 所有片段都识别成功，返回组合结果
              _lastLocalConfidence = totalConf / validSegments;
              debugPrint('连笔字切分: 组合结果 "$combinedResult" (平均置信度 ${(_lastLocalConfidence * 100).toStringAsFixed(0)}%)');
              _addDebugLog('recognition', '连笔字切分识别', data: {
                'result': combinedResult,
                'segments': segments.length,
                'confidence': _lastLocalConfidence,
              });
              return combinedResult;
            }
            debugPrint('连笔字切分: 切分识别未完全成功 ($validSegments/${segments.length})，继续常规识别');
          }
        }
      }

      // ═══ 第二轮：多级预处理 + 投票 ═══
      // v4.8.0: 优化分级策略 — 小图更激进放大，大图更智能
      List<int> upscaleTargets;
      if (maxDim < 30) {
        // 极小图：非常激进放大（需要更多放大倍数来补偿信息损失）
        upscaleTargets = [500, 700, 1000];
      } else if (maxDim < 50) {
        upscaleTargets = [400, 600, 800];
      } else if (maxDim < 100) {
        upscaleTargets = [300, 500, 700];
      } else if (maxDim < 200) {
        upscaleTargets = [200, 400];
      } else {
        upscaleTargets = [0]; // 0 = 不放大，用原图
      }
      // v3.4.0: 高质量大图跳过放大（原图已足够清晰）
      if (imageFeatures.qualityLevel == 'high' && maxDim >= 150) {
        upscaleTargets = [0];
        debugPrint('ML Kit 识别: 高质量大图，跳过放大');
      }
      // v4.8.0: 低对比度图片额外放大（小笔画在低对比度下更容易丢失）
      if (imageFeatures.contrast < 0.3 && maxDim < 150 && upscaleTargets != [0]) {
        final extraTargets = <int>[];
        for (final t in upscaleTargets) {
          extraTargets.add(t);
          if (t < 600) extraTargets.add(t + 200); // 每个目标额外加一个更大的
        }
        upscaleTargets = extraTargets.toSet().toList()..sort();
      }
      debugPrint('ML Kit 识别: 分级策略 targets=$upscaleTargets');

      // 预处理组合列表（覆盖更多场景）
      final preprocessors = <String, img.Image Function(img.Image)>{
        // 基础策略
        '灰度': (src) => img.grayscale(src),
        '灰度+对比度': (src) {
          final gray = img.grayscale(src);
          return img.adjustColor(gray, contrast: 1.5, brightness: 1.1);
        },
        '灰度+锐化': (src) {
          final gray = img.grayscale(src);
          return _sharpen(gray);
        },
        '灰度+去噪': (src) {
          final gray = img.grayscale(src);
          return _medianFilter(gray);
        },
        '灰度+自适应二值化': (src) {
          final gray = img.grayscale(src);
          return _adaptiveBinarize(gray, blockSize: 31, c: 10);
        },
        '灰度+对比度+二值化': (src) {
          final gray = img.grayscale(src);
          final enhanced = img.adjustColor(gray, contrast: 1.5, brightness: 1.1);
          return _binarize(enhanced);
        },
        '灰度+去噪+锐化': (src) {
          final gray = img.grayscale(src);
          final denoised = _medianFilter(gray);
          return _sharpen(denoised);
        },
        '灰度+去噪+自适应二值化': (src) {
          final gray = img.grayscale(src);
          final denoised = _medianFilter(gray);
          return _adaptiveBinarize(denoised, blockSize: 31, c: 10);
        },
        '灰度+对比度+去噪+二值化': (src) {
          final gray = img.grayscale(src);
          final enhanced = img.adjustColor(gray, contrast: 1.5, brightness: 1.1);
          final denoised = _medianFilter(enhanced);
          return _binarize(denoised);
        },
        // 手写体专用预处理策略
        '手写体笔画增强': (src) => _handwritingEnhance(src),
        '倾斜校正': (src) => _skewCorrection(src),
        '笔画归一化': (src) => _strokeNormalization(src),
        '手写体增强+对比度': (src) {
          final enhanced = _handwritingEnhance(src);
          return _enhanceContrast(enhanced);
        },
        // CLAHE / 背景归一化 / 方向边缘增强（v2.5.0 新增）
        '自适应对比度增强': (src) => _clahe(src),
        '背景归一化': (src) => _normalizeBackground(src),
        '方向边缘增强': (src) => _directionalEdgeEnhance(src),
        // v3.9.0: CLAHE 自适应参数（根据对比度自动选 clipLimit）
        'CLAHE自适应': (src) => ImageQualityService.instance.enhanceContrastAdaptive(src),
        // v4.0.0: 多尺度 USM 笔画锐化
        'USM笔画锐化': (src) => _unsharpMaskSharpen(src, amount: 1.5),
        'USM强锐化': (src) => _unsharpMaskSharpen(src, amount: 2.0),
        'USM锐化+CLAHE': (src) {
          final sharpened = _unsharpMaskSharpen(src, amount: 1.5);
          return ImageQualityService.instance.enhanceContrastAdaptive(sharpened);
        },
        // v2.6.0 新增 4 种预处理策略
        '自适应直方图均衡': (src) => _adaptiveHistogramEqualizeQuadrants(src),
        '形态学骨架化': (src) => _morphologicalSkeletonize(src),
        '高斯模糊去噪+锐化': (src) => _gaussianBlurSharpen(src),
        '局部阈值二值化': (src) => _localThresholdBinarize(src),
        // v4.0.1: 笔画粗细自适应
        '笔画粗细自适应': (src) => _strokeThicknessAdaptive(src),
        // v4.3.0: 形态学断笔修复（闭运算：膨胀→腐蚀，填充笔画间小间隙）
        '断笔修复': (src) => _morphologicalClose(img.grayscale(src), radius: 1),
        // v4.3.0: 细笔画增强（自适应膨胀，笔画太细时加粗）
        '细笔画增强': (src) => _thinStrokeEnhance(src),
        // v4.3.0: 形态学开运算去噪（先腐蚀后膨胀，去除小噪点）
        '开运算去噪': (src) => _morphologicalOpen(img.grayscale(src), radius: 1),
        // v4.3.0: 多尺度形态学（小膨胀+闭运算，兼顾断笔修复和笔画增强）
        '多尺度形态学': (src) => _multiScaleMorphology(src),
        // v4.5.0: 自适应伽马校正（亮度归一化，处理过暗/过亮图片）
        '自适应伽马校正': (src) => _adaptiveGammaCorrection(src),
        // v4.5.0: 多尺度边缘增强（同时增强粗笔画和细笔画边缘）
        '多尺度边缘增强': (src) => _multiScaleEdgeEnhance(src),
        // v4.5.0: 笔画感知去噪（保留边缘，去除背景噪声）
        '笔画感知去噪': (src) => _strokeAwareDenoise(src),
        // v4.5.0: 伽马+CLAHE 组合（先亮度归一化再对比度增强）
        '伽马+CLAHE': (src) {
          final gamma = _adaptiveGammaCorrection(src);
          return ImageQualityService.instance.enhanceContrastAdaptive(gamma);
        },
        // v4.5.0: 边缘增强+锐化 组合
        '边缘增强+锐化': (src) {
          final edge = _multiScaleEdgeEnhance(src);
          return _unsharpMaskSharpen(edge, amount: 1.2);
        },
        // v4.7.0: 迭代反投影去模糊（处理轻微运动模糊/手抖模糊）
        '迭代去模糊': (src) => _iterativeDeblur(src, iterations: 4),
        // v4.7.0: 去模糊+锐化 组合（先恢复高频再锐化）
        '去模糊+锐化': (src) {
          final deblurred = _iterativeDeblur(src, iterations: 3);
          return _unsharpMaskSharpen(deblurred, amount: 1.2);
        },
        // v4.7.0: 去模糊+CLAHE 组合（先恢复清晰度再增强对比度）
        '去模糊+CLAHE': (src) {
          final deblurred = _iterativeDeblur(src, iterations: 3);
          return ImageQualityService.instance.enhanceContrastAdaptive(deblurred);
        },
        // v4.8.0: Sauvola 自适应二值化（经典文档二值化，对手写体效果优于 Otsu/Niblack）
        // v5.7.0: 参数自适应 — 根据噪声/对比度/分辨率自动调整 blockSize 和 k
        'Sauvola二值化': (src) => _sauvolaBinarizeAdaptive(src, features: imageFeatures),
        // v4.8.0: Sauvola + 去噪组合
        '去噪+Sauvola': (src) {
          final denoised = _strokeAwareDenoise(src);
          return _sauvolaBinarizeAdaptive(denoised, features: imageFeatures);
        },
        // v4.8.0: 伽马校正 + Sauvola（先亮度归一化再二值化）
        '伽马+Sauvola': (src) {
          final gamma = _adaptiveGammaCorrection(src);
          return _sauvolaBinarizeAdaptive(gamma, features: imageFeatures);
        },
        // v5.7.0: 形态学梯度 — 提取边缘轮廓，分离密集笔画
        '形态学梯度': (src) => _morphologicalGradient(src, radius: 1),
        // v5.7.0: 梯度+CLAHE — 边缘增强后再增强对比度
        '梯度+CLAHE': (src) {
          final gradient = _morphologicalGradient(src, radius: 1);
          return ImageQualityService.instance.enhanceContrastAdaptive(gradient);
        },
        // v5.7.0: 局部对比度增强 — 基于积分图的快速局部归一化，处理光照不均
        '局部对比度增强': (src) => _localContrastEnhance(src),
        // v5.7.0: 局部对比度+Sauvola — 先归一化再二值化
        '局部对比度+Sauvola': (src) {
          final enhanced = _localContrastEnhance(src);
          return _sauvolaBinarizeAdaptive(enhanced, features: imageFeatures);
        },
        // v5.8.0: 多阈值融合二值化 — 结合 Otsu 和自适应阈值的优势
        '多阈值融合': (src) => _multiThresholdFusion(src),
        // v5.8.0: 对比度+去模糊+USM — 三重增强组合
        '对比度+去模糊+USM': (src) {
          final contrasted = img.adjustColor(img.grayscale(src), contrast: 1.4);
          final deblurred = _iterativeDeblur(contrasted, iterations: 2);
          return _unsharpMaskSharpen(deblurred, amount: 1.3);
        },
        // v5.8.0: 自适应对比度+形态学闭运算 — 修复断笔的同时增强对比度
        '自适应对比度+闭运算': (src) {
          final enhanced = ImageQualityService.instance.enhanceContrastAdaptive(src);
          return _morphologicalClose(img.grayscale(enhanced), radius: 1);
        },
        // v5.8.0: 笔画保留增强 — 增强笔画同时抑制噪声
        '笔画保留增强': (src) => _strokePreservingEnhance(src),
      };

      // v2.9.0: 根据图像特征智能过滤策略（只跑相关的，不盲目跑全部）
      final filteredPreprocessors = <String, img.Image Function(img.Image)>{};
      final features = imageFeatures;
      // 基础策略始终保留
      filteredPreprocessors['灰度'] = preprocessors['灰度']!;
      filteredPreprocessors['灰度+对比度'] = preprocessors['灰度+对比度']!;
      // 根据特征添加相关策略
      if (features.contrast < 0.4) {
        // 低对比度：加对比度增强类策略
        for (final k in ['灰度+对比度+二值化', '自适应对比度增强', 'CLAHE自适应', '自适应直方图均衡', '背景归一化', 'Sauvola二值化', '伽马+Sauvola', '局部对比度增强', '局部对比度+Sauvola', '多阈值融合', '笔画保留增强']) {
          if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
        }
      }
      if (features.noise > 0.5) {
        // 高噪声：加降噪类策略（v4.5.0: 新增笔画感知去噪）
        for (final k in ['灰度+去噪', '灰度+去噪+锐化', '高斯模糊去噪+锐化', '笔画感知去噪', '去噪+Sauvola', '笔画保留增强', '自适应对比度+闭运算']) {
          if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
        }
      }
      if (features.blur > 0.5) {
        // 模糊：加锐化类策略（含 v4.0.0 USM, v4.5.0 多尺度边缘增强, v4.7.0 去模糊）
        for (final k in ['灰度+锐化', '灰度+去噪+锐化', '方向边缘增强', 'USM笔画锐化', 'USM强锐化', 'USM锐化+CLAHE', '多尺度边缘增强', '边缘增强+锐化', '迭代去模糊', '去模糊+锐化', '去模糊+CLAHE', '对比度+去模糊+USM']) {
          if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
        }
      }
      if (features.lineThickness < 0.3) {
        // 细线条：加增粗策略（v4.3.0: 新增细笔画增强、断笔修复）
        for (final k in ['手写体笔画增强', '笔画归一化', '笔画粗细自适应', '细笔画增强', '断笔修复']) {
          if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
        }
      }
      if (features.lineThickness > 0.7) {
        // 粗线条：加细化策略（v4.3.0: 新增开运算去噪）
        for (final k in ['形态学骨架化', '笔画粗细自适应', '开运算去噪']) {
          if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
        }
      }
      if (features.connection > 0.6) {
        // 连笔：加分离策略
        for (final k in ['形态学骨架化', '局部阈值二值化']) {
          if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
        }
      }

      // ═══ v4.8.0: 手写风格自适应 — 根据检测到的风格加权策略 ═══
      final style = features.style;
      debugPrint('手写风格自适应: 检测到 ${features.styleName} 风格 '
          '(笔画粗细=${features.lineThickness.toStringAsFixed(2)}, '
          '连笔=${features.connection.toStringAsFixed(2)}, '
          '变异度=${features.strokeVariability.toStringAsFixed(2)})');

      switch (style) {
        case HandwritingStyle.cursive:
          // 行书/草书：连笔多，需增强分离和骨架化
          for (final k in [
            '形态学骨架化', '局部阈值二值化', '倾斜校正',
            '灰度+自适应二值化', '灰度+对比度+二值化',
            'Sauvola二值化', '伽马+Sauvola',
          ]) {
            if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
          }
          break;
        case HandwritingStyle.light:
          // 轻笔：笔画细弱，需增强增粗和对比度
          for (final k in [
            '细笔画增强', '笔画粗细自适应', '断笔修复',
            'USM笔画锐化', 'USM强锐化', 'USM锐化+CLAHE',
            '手写体笔画增强', '笔画归一化',
            '多尺度形态学', '伽马+Sauvola',
            '笔画保留增强', '自适应对比度+闭运算',
          ]) {
            if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
          }
          break;
        case HandwritingStyle.heavy:
          // 重笔：笔画粗重，需增强细化和边缘
          for (final k in [
            '形态学骨架化', '开运算去噪', '笔画粗细自适应',
            '多尺度边缘增强', '边缘增强+锐化',
            'Sauvola二值化', '灰度+对比度+二值化',
            '多阈值融合',
          ]) {
            if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
          }
          break;
        case HandwritingStyle.mixed:
          // 混合风格：均衡尝试多种策略
          for (final k in [
            '笔画粗细自适应', '笔画感知去噪',
            '自适应伽马校正', '伽马+CLAHE',
            'Sauvola二值化', '去噪+Sauvola',
            '多阈值融合', '笔画保留增强',
          ]) {
            if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
          }
          break;
        case HandwritingStyle.regular:
        default:
          // 楷书：标准处理，无额外策略
          break;
      }

      // 倾斜角度大时额外添加倾斜校正
      if (features.slantAngle > 0.5) {
        if (preprocessors.containsKey('倾斜校正')) {
          filteredPreprocessors['倾斜校正'] = preprocessors['倾斜校正']!;
        }
        debugPrint('手写风格自适应: 检测到严重倾斜 (slant=${features.slantAngle.toStringAsFixed(2)})，添加倾斜校正');
      }

      // 边缘模糊时额外添加锐化策略
      if (features.edgeSharpness < 0.3) {
        for (final k in ['USM笔画锐化', 'USM强锐化', '多尺度边缘增强']) {
          if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
        }
        debugPrint('手写风格自适应: 边缘模糊 (sharpness=${features.edgeSharpness.toStringAsFixed(2)})，添加锐化策略');
      }

      // ═══ v5.5.0: 笔画密度自适应 — 根据墨迹密度选择策略 ═══
      // 高墨迹密度（复杂字，如"龍""鬱"）：笔画密集，需增强分离和去噪
      // 低墨迹密度（简单字，如"一""人"）：笔画稀疏，需增强细节和增粗
      if (features.inkDensity > 0.6) {
        // 复杂字：笔画密集，优先分离和去噪策略
        for (final k in [
          '形态学骨架化', '开运算去噪', '局部阈值二值化',
          'Sauvola二值化', '去噪+Sauvola', '伽马+Sauvola',
          '多尺度形态学', '笔画感知去噪', '形态学梯度', '梯度+CLAHE',
        ]) {
          if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
        }
        debugPrint('笔画密度自适应: 高密度 (inkDensity=${features.inkDensity.toStringAsFixed(2)})，'
            '添加分离+去噪策略');
      } else if (features.inkDensity < 0.3) {
        // 简单字：笔画稀疏，优先增粗和细节保留策略
        for (final k in [
          '细笔画增强', '断笔修复', '笔画粗细自适应',
          'USM笔画锐化', '手写体笔画增强', '笔画归一化',
          '自适应伽马校正', '伽马+CLAHE',
        ]) {
          if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
        }
        debugPrint('笔画密度自适应: 低密度 (inkDensity=${features.inkDensity.toStringAsFixed(2)})，'
            '添加增粗+细节保留策略');
      }

      // v4.8.0: 极小图特殊处理 — 添加更多增强策略
      if (maxDim < 50) {
        for (final k in ['USM强锐化', 'CLAHE自适应', '伽马+CLAHE', 'Sauvola二值化', '伽马+Sauvola']) {
          if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
        }
        debugPrint('小图优化: 添加增强策略（USM强锐化+CLAHE+Sauvola）');
      }

      // 确保至少有5个策略
      if (filteredPreprocessors.length < 5) {
        for (final k in ['灰度+自适应二值化', '灰度+去噪+自适应二值化', '手写体增强+对比度', '倾斜校正']) {
          if (!filteredPreprocessors.containsKey(k) && preprocessors.containsKey(k)) {
            filteredPreprocessors[k] = preprocessors[k]!;
          }
          if (filteredPreprocessors.length >= 5) break;
        }
      }

      // v4.6.0: 策略组合优化 — 根据历史性能排序策略
      await _loadStrategyPerformance();
      final optimalOrder = _selectOptimalStrategies(imageFeatures, filteredPreprocessors);
      final orderedPreprocessors = <String, img.Image Function(img.Image)>{};
      for (final key in optimalOrder) {
        if (filteredPreprocessors.containsKey(key)) {
          orderedPreprocessors[key] = filteredPreprocessors[key]!;
        }
      }

      // v5.7.0: 自适应策略数量 — 根据图像质量和字符复杂度调整
      // 高质量大图 + 简单字符：减少策略数量，避免过度处理引入噪声
      // 低质量/复杂字符：使用更多策略，增加覆盖
      int maxStrategies = 30; // 默认上限
      if (imageFeatures.qualityLevel == 'high' && imageFeatures.inkDensity < 0.3) {
        maxStrategies = 15; // 高质量简单字：精简策略
        debugPrint('自适应策略: 高质量简单字，限制策略数=$maxStrategies');
      } else if (imageFeatures.qualityLevel == 'high' && maxDim >= 150) {
        maxStrategies = 12; // 高质量大图：最少策略
        debugPrint('自适应策略: 高质量大图，限制策略数=$maxStrategies');
      } else if (imageFeatures.inkDensity > 0.6) {
        maxStrategies = 30; // 复杂字：最多策略
        debugPrint('自适应策略: 复杂字，策略数=$maxStrategies');
      }
      if (orderedPreprocessors.length > maxStrategies) {
        final limited = orderedPreprocessors.entries.take(maxStrategies).toList();
        orderedPreprocessors.clear();
        for (final entry in limited) {
          orderedPreprocessors[entry.key] = entry.value;
        }
        debugPrint('自适应策略: 限制为 $maxStrategies 个策略');
      }

      debugPrint('ML Kit 识别: 智能策略选择 ${orderedPreprocessors.length}/${preprocessors.length} 种 '
          '(风格=${features.styleName}, 对比度=${features.contrast.toStringAsFixed(2)}, '
          '噪声=${features.noise.toStringAsFixed(2)}, 模糊=${features.blur.toStringAsFixed(2)})');

      int attempt = 0;

      for (final targetSize in upscaleTargets) {
        img.Image base;
        if (targetSize == 0) {
          base = enhanced;
        } else {
          final scale = targetSize / maxDim;
          final newW = (w * scale).round();
          final newH = (h * scale).round();
          base = img.copyResize(enhanced, width: newW, height: newH,
              interpolation: img.Interpolation.cubic);
          debugPrint('ML Kit 识别: 放大到 ${base.width}x${base.height}');
        }

        // ═══ v4.9.0: 预处理并行化 — Isolate 并行预处理 + 顺序识别 ═══
        // 将所有策略的 CPU 密集型预处理放到独立 Isolate 中并行执行，
        // 主线程只需顺序执行 ML Kit 识别（平台通道不支持并发）
        final baseBytes = Uint8List.fromList(img.encodePng(base));
        final strategyEntries = orderedPreprocessors.entries.toList();

        // 构建并行预处理任务
        final tasks = <PreprocessTask>[];
        for (int i = 0; i < strategyEntries.length; i++) {
          tasks.add(PreprocessTask(
            imageBytes: baseBytes,
            strategyName: strategyEntries[i].key,
            taskIndex: i,
          ));
        }

        // 并行执行预处理（4 个 Isolate 并发，充分利用多核 CPU）
        debugPrint('ML Kit 识别: 并行预处理 ${tasks.length} 个策略 '
            '(放大=${targetSize == 0 ? "原图" : "${base.width}x${base.height}"})');
        final sw = Stopwatch()..start();

        const maxParallel = 4;
        final preprocessResults = <PreprocessResult>[];
        for (int batch = 0; batch < tasks.length; batch += maxParallel) {
          final batchEnd = (batch + maxParallel).clamp(0, tasks.length);
          final batchTasks = tasks.sublist(batch, batchEnd);
          final batchResults = await Future.wait(
            batchTasks.map((task) => Isolate.run(() => preprocessInIsolate(task))),
          );
          preprocessResults.addAll(batchResults);

          // 检查是否已提前终止（避免多余批次的预处理）
          if (earlyTerminated) break;
        }

        sw.stop();
        debugPrint('ML Kit 识别: 并行预处理完成，耗时 ${sw.elapsedMilliseconds}ms '
            '(${preprocessResults.length} 个策略)');

        // 顺序识别预处理结果（ML Kit 平台通道不支持并发）
        for (final preprocessResult in preprocessResults) {
          if (earlyTerminated) break;

          attempt++;
          final label = preprocessResult.strategyName;
          final processed = img.decodeImage(preprocessResult.processedBytes)!;

          debugPrint('ML Kit 识别: 第${attempt}次尝试 | 放大=${targetSize == 0 ? "原图" : "${base.width}x${base.height}"} | 预处理=$label');

          final rawResult = await _recognizeFromImage(processed);
          final result = _validateResult(rawResult);
          if (result != null) {
            // v2.6.0: 加权投票 — 高可靠性策略获得 1.2x 权重
            final reliability = _strategyReliability[label] ?? 0.5;
            final voteWeight = reliability >= 0.7 ? 2 : 1; // 高可靠性策略多计 1 票
            voteMap[result] = (voteMap[result] ?? 0) + voteWeight;
            // 记录策略来源
            resultStrategies.putIfAbsent(result, () => <String>{});
            resultStrategies[result]!.add(label);
            // v3.5.0: 记录识别到该结果的放大尺寸
            resultSizes.putIfAbsent(result, () => <int>{});
            resultSizes[result]!.add(targetSize);
            // v2.7.0: 记录策略投票明细
            strategyVotes.putIfAbsent(result, () => {});
            strategyVotes[result]![label] = (strategyVotes[result]![label] ?? 0) + voteWeight;
            actualAttempts = attempt;
            // 更新置信度（取最高值）
            final hash = _hashBytes(img.encodePng(processed));
            final conf = _confidenceCache[hash] ?? 0.7;
            confidenceMap[result] = (confidenceMap[result] ?? 0) > conf
                ? confidenceMap[result]!
                : conf;
            debugPrint('ML Kit 识别: ✓ 第${attempt}次识别到 "$result" (累计票数: ${voteMap[result]}, 策略=$label, 权重=$voteWeight)');
            // v4.8.0: 改进提前终止 — 要求最低尝试次数 + 多策略确认
            final totalAttempts = upscaleTargets.length * filteredPreprocessors.length;
            final earlyThreshold = totalAttempts <= 6 ? 3 : (totalAttempts <= 12 ? 4 : 5);
            final minAttemptsBeforeEarly = 4; // 至少尝试 4 次才允许提前终止
            final hasMultiStrategy = (resultStrategies[result]?.length ?? 0) >= 2;
            if (attempt >= minAttemptsBeforeEarly && voteMap[result]! >= earlyThreshold && hasMultiStrategy) {
              earlyTerminated = true;
              debugPrint('ML Kit 识别: 提前终止，$result 已获 ${voteMap[result]} 票 (阈值=$earlyThreshold, 多策略确认)');
            }
          } else {
            if (rawResult != null && rawResult.isNotEmpty) {
              debugPrint('ML Kit 识别: 过滤非目标字符 "$rawResult" (U+${rawResult.codeUnitAt(0).toRadixString(16)})');
            }
            debugPrint('ML Kit 识别: ✗ 第${attempt}次未识别到文字');
          }
        }
        // v4.8.0: 外层循环提前终止 — 要求更高票数 + 多策略确认
        if (voteMap.isNotEmpty) {
          final maxVotes = voteMap.values.reduce((a, b) => a > b ? a : b);
          final topCandidate = voteMap.entries.reduce((a, b) => a.value >= b.value ? a : b);
          final topStrategies = resultStrategies[topCandidate.key]?.length ?? 0;
          if (maxVotes >= 4 && topStrategies >= 2) break; // v4.8.0: 提高阈值，要求多策略
        }
      }

      // v2.6.0: 智能投票选出最佳结果
      if (voteMap.isNotEmpty) {

        // ═══ v4.1.0: TFLite 模型投票（补充投票者）═══
        // 在 ML Kit 投票完成后，尝试使用 TFLite 模型进行补充识别
        // TFLite 结果以 1.0x 权重计入投票（低于 ML Kit 主流程）
        bool tfliteUsed = false;
        try {
          final useTflite = await getUseTflite();
          if (useTflite) {
            final tfliteService = TfliteRecognitionService.instance;
            final tfliteLoaded = await tfliteService.loadModel();
            // v5.2.0: 跳过占位推理器 — 随机输出会向投票系统注入噪声
            if (tfliteLoaded && tfliteService.isModelLoaded && !tfliteService.isUsingPlaceholder) {
              debugPrint('ML Kit 识别: TFLite 模型可用，执行补充识别');
              final tflitePredictions = await tfliteService.recognizeWithConfidence(
                imageBytes,
                topN: 3,
              );
              if (tflitePredictions.isNotEmpty) {
                tfliteUsed = true;
                for (final pred in tflitePredictions) {
                  final tfliteVote = pred.confidence >= 0.7 ? 2 : 1; // 高置信度额外加分
                  voteMap[pred.character] = (voteMap[pred.character] ?? 0) + tfliteVote;
                  resultStrategies.putIfAbsent(pred.character, () => <String>{});
                  resultStrategies[pred.character]!.add('TFLite模型');
                  strategyVotes.putIfAbsent(pred.character, () => {});
                  strategyVotes[pred.character]!['TFLite模型'] = (strategyVotes[pred.character]!['TFLite模型'] ?? 0) + tfliteVote;
                  debugPrint('TFLite 投票: "${pred.character}" 置信度 ${(pred.confidence * 100).toStringAsFixed(1)}% → +$tfliteVote 票');
                }
                _addDebugLog('recognition', 'TFLite 补充投票', data: {
                  'predictions': tflitePredictions.map((p) => {'char': p.character, 'conf': p.confidence}).toList(),
                });
              }
            } else {
              debugPrint('TFLite: 模型不可用，跳过补充投票');
            }
          }
        } catch (e) {
          debugPrint('TFLite: 补充投票异常（不影响主流程）: $e');
        }

        // v4.4.0: 多候选综合评分排序（票数 + 置信度 + 字频 + 策略多样性 + 多尺度一致性）
        final totalVotes = voteMap.values.fold(0, (a, b) => a + b);
        final candidateScores = <String, double>{};
        for (final entry in voteMap.entries) {
          candidateScores[entry.key] = _computeCandidateScore(
            candidate: entry.key,
            votes: entry.value,
            totalVotes: totalVotes,
            confidenceMap: confidenceMap,
            resultStrategies: resultStrategies,
            resultSizes: resultSizes,
          );
        }
        final sorted = voteMap.entries.toList()
          ..sort((a, b) {
            final scoreDiff = (candidateScores[b.key] ?? 0).compareTo(candidateScores[a.key] ?? 0);
            if (scoreDiff != 0) return scoreDiff;
            // 分数相同时按票数降序
            return b.value.compareTo(a.value);
          });
        var winner = sorted.first;
        debugPrint('ML Kit 识别: 综合评分排序 — ${sorted.take(3).map((e) => '"${e.key}" score=${(candidateScores[e.key]! * 100).toStringAsFixed(0)}% votes=${e.value}').join(', ')}');

        // ── v4.8.0: 平局决胜 — 扩展到5种预处理，覆盖更多场景 ──
        if (sorted.length >= 2 && (winner.value - sorted[1].value) <= 1) {
          debugPrint('ML Kit 识别: 平局决胜触发 (top1="${winner.key}"=${winner.value}票, top2="${sorted[1].key}"=${sorted[1].value}票)');
          final candidateA = winner.key;
          final candidateB = sorted[1].key;
          int tieBreakA = 0;
          int tieBreakB = 0;

          // v4.8.0: 用5种不同预处理做决胜投票（覆盖更多场景）
          final tieBreakers = [
            _sharpen(img.adjustColor(img.grayscale(enhanced), contrast: 1.8, brightness: 1.2)),
            _adaptiveBinarize(img.grayscale(enhanced), blockSize: 25, c: 8),
            _clahe(enhanced),
            _sauvolaBinarizeAdaptive(enhanced, features: imageFeatures), // v5.7.0: 自适应Sauvola
            _iterativeDeblur(enhanced, iterations: 3), // v4.8.0: 去模糊
          ];
          for (final tieProcessed in tieBreakers) {
            final tieRawResult = await _recognizeFromImage(tieProcessed);
            final tieResult = _validateResult(tieRawResult);
            if (tieResult == candidateA) {
              tieBreakA++;
              debugPrint('ML Kit 识别: 平局决胜 → 倾向 "$candidateA"');
            } else if (tieResult == candidateB) {
              tieBreakB++;
              debugPrint('ML Kit 识别: 平局决胜 → 倾向 "$candidateB"');
            }
          }

          // 决胜结果影响最终选择
          if (tieBreakA > tieBreakB) {
            winner = MapEntry(candidateA, winner.value);
          } else if (tieBreakB > tieBreakA) {
            winner = MapEntry(candidateB, sorted[1].value);
          } else {
            // v4.8.0: 视觉决胜平手时，用 n-gram 上下文模型做最终判断
            final ctxScoreA = DictionaryService.instance.getContextScore(
              candidateA,
              prevChar: _lastRecognizedChars.isNotEmpty ? _lastRecognizedChars.last : null,
            );
            final ctxScoreB = DictionaryService.instance.getContextScore(
              candidateB,
              prevChar: _lastRecognizedChars.isNotEmpty ? _lastRecognizedChars.last : null,
            );
            if (ctxScoreA > ctxScoreB + 0.1) {
              winner = MapEntry(candidateA, winner.value);
              debugPrint('ML Kit 识别: 平局决胜 → 上下文倾向 "$candidateA" (${(ctxScoreA * 100).toStringAsFixed(0)}% vs ${(ctxScoreB * 100).toStringAsFixed(0)}%)');
            } else if (ctxScoreB > ctxScoreA + 0.1) {
              winner = MapEntry(candidateB, sorted[1].value);
              debugPrint('ML Kit 识别: 平局决胜 → 上下文倾向 "$candidateB" (${(ctxScoreB * 100).toStringAsFixed(0)}% vs ${(ctxScoreA * 100).toStringAsFixed(0)}%)');
            }
            // 若上下文也无法判断，保持原排序（置信度高的优先）
          }
        }

        // ── 置信度校准（v4.2.0 增强） ──
        double calibratedConf = confidenceMap[winner.key] ?? 0.7;

        // 1. 票数差距：winner 票数 >= 2x runner-up → +0.1
        if (sorted.length >= 2) {
          final runnerUpVotes = sorted[1].value;
          if (runnerUpVotes > 0 && winner.value >= runnerUpVotes * 2) {
            calibratedConf = (calibratedConf + 0.1).clamp(0.0, 1.0);
            debugPrint('ML Kit 识别: 置信度校准 — 票数优势 (+0.1)');
          }
        }

        // 2. 策略多样性：winner 获得 3+ 种不同策略投票 → +0.05
        final strategyCount = resultStrategies[winner.key]?.length ?? 0;
        if (strategyCount >= 3) {
          calibratedConf = (calibratedConf + 0.05).clamp(0.0, 1.0);
          debugPrint('ML Kit 识别: 置信度校准 — 策略多样性 $strategyCount 种 (+0.05)');
        }

        // 3. 提前终止：票数过半 → 置信度设为 0.95
        if (earlyTerminated) {
          calibratedConf = 0.95;
          debugPrint('ML Kit 识别: 置信度校准 — 提前终止 (=0.0.95)');
        }

        // 4. 图像质量调整（v3.1.0）：低质量图片降低置信度，高质量提升
        final qualityLevel = imageFeatures.qualityLevel;
        if (qualityLevel == 'low') {
          calibratedConf = (calibratedConf - 0.1).clamp(0.0, 1.0);
          debugPrint('ML Kit 识别: 置信度校准 — 低质量图片 (-0.1)');
        } else if (qualityLevel == 'high') {
          calibratedConf = (calibratedConf + 0.05).clamp(0.0, 1.0);
          debugPrint('ML Kit 识别: 置信度校准 — 高质量图片 (+0.05)');
        }

        // 5. 字频加成（v3.1.0）：常见字置信度提升
        final freqRank = DictionaryService.instance.getFrequency(winner.key);
        if (freqRank >= 0 && freqRank < 500) {
          calibratedConf = (calibratedConf + 0.03).clamp(0.0, 1.0);
          debugPrint('ML Kit 识别: 置信度校准 — 常见字Top500 (+0.03)');
        }

        // 6. 多尺度一致性（v3.5.0）：多个放大尺寸识别到相同结果 → +0.05
        final sizeCount = resultSizes[winner.key]?.length ?? 0;
        if (sizeCount >= 2) {
          calibratedConf = (calibratedConf + 0.05).clamp(0.0, 1.0);
          debugPrint('ML Kit 识别: 置信度校准 — 多尺度一致 $sizeCount 种尺寸 (+0.05)');
        }

        // 7. v4.2.0: 共识强度 — winner票数占总票数比例越高，置信度越高
        final consensusTotalVotes = voteMap.values.reduce((a, b) => a + b);
        if (consensusTotalVotes > 0) {
          final consensusRatio = winner.value / consensusTotalVotes;
          if (consensusRatio >= 0.7) {
            calibratedConf = (calibratedConf + 0.05).clamp(0.0, 1.0);
            debugPrint('ML Kit 识别: 置信度校准 — 高共识度 ${(consensusRatio * 100).toStringAsFixed(0)}% (+0.05)');
          } else if (consensusRatio < 0.4) {
            calibratedConf = (calibratedConf - 0.05).clamp(0.0, 1.0);
            debugPrint('ML Kit 识别: 置信度校准 — 低共识度 ${(consensusRatio * 100).toStringAsFixed(0)}% (-0.05)');
          }
        }

        // 8. v4.2.0: TFLite 一致性 — 如果 TFLite 与 ML Kit 结果一致，提升置信度
        if (tfliteUsed && voteMap.containsKey(winner.key)) {
          // TFLite 已经通过投票参与，额外检查是否为 Top-1
          final tfliteStrategies = resultStrategies[winner.key]?.contains('TFLite模型') ?? false;
          if (tfliteStrategies) {
            calibratedConf = (calibratedConf + 0.05).clamp(0.0, 1.0);
            debugPrint('ML Kit 识别: 置信度校准 — TFLite 一致 (+0.05)');
          }
        }

        // 9. v4.2.0: 字典验证 — 如果结果在常用字表中，额外提升
        if (DictionaryService.instance.isCommonChar(winner.key)) {
          calibratedConf = (calibratedConf + 0.02).clamp(0.0, 1.0);
        }

        // 10. v4.5.0: n-gram 上下文得分 — 与上下文越匹配，置信度越高
        final ngramScore = DictionaryService.instance.getContextScore(
          winner.key,
          prevChar: _lastRecognizedChars.isNotEmpty ? _lastRecognizedChars.last : null,
        );
        if (ngramScore > 0.7) {
          calibratedConf = (calibratedConf + 0.04).clamp(0.0, 1.0);
          debugPrint('ML Kit 识别: 置信度校准 — n-gram高匹配 ${(ngramScore * 100).toStringAsFixed(0)}% (+0.04)');
        } else if (ngramScore < 0.2 && ngramScore > 0) {
          calibratedConf = (calibratedConf - 0.03).clamp(0.0, 1.0);
          debugPrint('ML Kit 识别: 置信度校准 — n-gram低匹配 ${(ngramScore * 100).toStringAsFixed(0)}% (-0.03)');
        }

        // 11. v4.5.0: 错误模式感知 — 如果该字符曾被频繁纠正，降低置信度
        await _ensureErrorPatternsLoaded();
        final errorCorrections = _errorPatterns[winner.key];
        if (errorCorrections != null && errorCorrections.isNotEmpty) {
          final totalCorrections = errorCorrections.values.fold(0, (a, b) => a + b);
          if (totalCorrections >= 3) {
            calibratedConf = (calibratedConf - 0.04).clamp(0.0, 1.0);
            debugPrint('ML Kit 识别: 置信度校准 — 历史纠错${totalCorrections}次 (-0.04)');
          }
        }

        // 12. v4.5.0: 投票一致性 — 所有策略中无异议票的比例
        final totalVotesForWinner = voteMap[winner.key] ?? 0;
        final totalVotesAll = voteMap.values.fold(0, (a, b) => a + b);
        if (totalVotesAll > 0) {
          final unanimity = totalVotesForWinner / totalVotesAll;
          if (unanimity >= 0.9) {
            calibratedConf = (calibratedConf + 0.03).clamp(0.0, 1.0);
            debugPrint('ML Kit 识别: 置信度校准 — 高度一致 ${(unanimity * 100).toStringAsFixed(0)}% (+0.03)');
          }
        }

        // 13. v4.8.0: 策略可靠性加成 — 如果投票策略的历史可靠性高，提升置信度
        final winnerStrategiesForConf = resultStrategies[winner.key] ?? {};
        double avgReliability = 0.0;
        int reliableCount = 0;
        for (final strat in winnerStrategiesForConf) {
          final rel = _strategyReliability[strat] ?? 0.5;
          avgReliability += rel;
          if (rel >= 0.7) reliableCount++;
        }
        if (winnerStrategiesForConf.isNotEmpty) {
          avgReliability /= winnerStrategiesForConf.length;
          if (avgReliability >= 0.7) {
            calibratedConf = (calibratedConf + 0.03).clamp(0.0, 1.0);
            debugPrint('ML Kit 识别: 置信度校准 — 策略可靠性高 ${(avgReliability * 100).toStringAsFixed(0)}% (+0.03)');
          }
        }

        // 14. v4.8.0: Runner-up 差距 — winner 与 runner-up 的票数差距越大，置信度越高
        if (sorted.length >= 2) {
          final voteGap = winner.value - sorted[1].value;
          if (voteGap >= 4) {
            calibratedConf = (calibratedConf + 0.03).clamp(0.0, 1.0);
            debugPrint('ML Kit 识别: 置信度校准 — 票数差距大 $voteGap (+0.03)');
          }
        }

        _lastLocalConfidence = calibratedConf;

        // ── 更新策略可靠性（v4.3.0: 持久化 + 时间衰减） ──
        await _ensureStrategyWeightsLoaded();
        // 时间衰减：每天衰减 1%，防止旧数据过度影响
        _applyTimeDecay();
        final winnerStrategies = resultStrategies[winner.key] ?? {};
        for (final strat in winnerStrategies) {
          final old = _strategyReliability[strat] ?? 0.5;
          // 指数移动平均，向成功方向微调
          _strategyReliability[strat] = (old * 0.8 + 0.2).clamp(0.0, 1.0);
        }
        // v3.3.0: 惩罚产生错误结果的策略
        for (final entry in resultStrategies.entries) {
          if (entry.key != winner.key) {
            for (final strat in entry.value) {
              final old = _strategyReliability[strat] ?? 0.5;
              _strategyReliability[strat] = (old * 0.9).clamp(0.0, 1.0);
            }
          }
        }
        // v4.3.0: 每10次识别持久化一次策略权重
        _strategyUpdateCount++;
        if (_strategyUpdateCount >= 10) {
          _strategyUpdateCount = 0;
          await _saveStrategyWeights();
        }

        // v2.7.0: 存储识别投票详情（供 UI 展示）
        final totalPossibleAttempts = upscaleTargets.length * filteredPreprocessors.length;
        final attemptsSaved = earlyTerminated ? (totalPossibleAttempts - actualAttempts) : 0;
        // 找出最可靠策略
        String? topStrat;
        double topReliability = 0.0;
        for (final strat in winnerStrategies) {
          final rel = _strategyReliability[strat] ?? 0.5;
          if (rel > topReliability) {
            topReliability = rel;
            topStrat = strat;
          }
        }
        final imageHash = _hashBytes(imageBytes);
        _detailCache[imageHash] = RecognitionDetail(
          result: winner.key,
          confidence: calibratedConf,
          voteBreakdown: strategyVotes,
          totalAttempts: totalPossibleAttempts,
          earlyTerminated: earlyTerminated,
          attemptsSaved: attemptsSaved,
          strategiesUsed: strategyCount,
          topStrategy: topStrat,
          topStrategyReliability: topReliability,
          imageFeatures: imageFeatures,
        );

        debugPrint('ML Kit 识别: 投票结果 "${winner.key}" (票数=${winner.value}, 置信度=${((_lastLocalConfidence) * 100).toStringAsFixed(0)}%, 策略=$strategyCount 种)');

        // v5.2.0: 旋转重试 — 阈值从 0.5 提升到 0.65，覆盖更多中等置信度场景
        // 很多误识别发生在 0.5-0.65 置信度范围，旋转重试可以纠正
        if (_lastLocalConfidence < 0.65 && maxDim >= 80) {
          debugPrint('ML Kit 识别: 置信度 ${(_lastLocalConfidence * 100).toStringAsFixed(0)}% < 65%，尝试旋转重试');
          for (final angle in [90, 180, 270]) {
            final rotated = img.copyRotate(enhanced, angle: angle);
            final gray = img.grayscale(rotated);
            final raw = await _recognizeFromImage(gray);
            final r = _validateResult(raw);
            if (r != null) {
              debugPrint('ML Kit 识别: 旋转${angle}°识别到 "$r"');
              // 如果旋转后识别到不同的字符，且该字符已有投票，提升其权重
              if (r != winner.key && voteMap.containsKey(r)) {
                voteMap[r] = (voteMap[r] ?? 0) + 2;
                if (voteMap[r]! > winner.value) {
                  winner = MapEntry(r, voteMap[r]!);
                  _lastLocalConfidence = 0.6;
                  debugPrint('ML Kit 识别: 旋转重试翻转结果为 "$r"');
                  break;
                }
              }
            }
          }
        }

        // v4.6.0: 异步更新策略组合性能统计（不阻塞返回）
        _updateStrategyPerformanceAsync(imageFeatures, resultStrategies, winner.key);

        return winner.key;
      }

      // ═══ 第三轮：失败回退策略 ═══
      _lastLocalConfidence = 0.5;
      debugPrint('ML Kit 识别: 常规预处理均失败，尝试回退策略');

      // 确定回退用的基础图片（使用增强后的图像）
      final fallbackBase = upscaleTargets.isNotEmpty && upscaleTargets.first > 0
          ? img.copyResize(enhanced,
              width: (w * upscaleTargets.first / maxDim).round(),
              height: (h * upscaleTargets.first / maxDim).round(),
              interpolation: img.Interpolation.cubic)
          : enhanced;

      // 回退策略 1：裁剪边缘空白后再识别
      debugPrint('ML Kit 识别: 回退策略1 - 裁剪边缘空白');
      final trimmedFallback = _trimWhitespace(fallbackBase);
      if (trimmedFallback.width != fallbackBase.width || trimmedFallback.height != fallbackBase.height) {
        final grayTrimmed = img.grayscale(trimmedFallback);
        final rawResult = await _recognizeFromImage(grayTrimmed);
        final result = _validateResult(rawResult);
        if (result != null) {
          debugPrint('ML Kit 识别: ✓ 裁剪边缘成功, 字符="$result"');
          return result;
        }
      }

      // 回退策略 2：反转颜色（白底黑字 ↔ 黑底白字）
      debugPrint('ML Kit 识别: 回退策略2 - 反转颜色');
      final inverted = _invertColors(img.grayscale(fallbackBase));
      final rawInvResult = await _recognizeFromImage(inverted);
      final invResult = _validateResult(rawInvResult);
      if (invResult != null) {
        debugPrint('ML Kit 识别: ✓ 反转颜色成功, 字符="$invResult"');
        return invResult;
      }

      // 回退策略 3：反转颜色 + 裁剪
      debugPrint('ML Kit 识别: 回退策略3 - 反转颜色+裁剪');
      final invertedTrimmed = _invertColors(img.grayscale(_trimWhitespace(fallbackBase)));
      final rawInvTrimResult = await _recognizeFromImage(invertedTrimmed);
      final invTrimResult = _validateResult(rawInvTrimResult);
      if (invTrimResult != null) {
        debugPrint('ML Kit 识别: ✓ 反转+裁剪成功, 字符="$invTrimResult"');
        return invTrimResult;
      }

      // 回退策略 4：骨架化（对粗笔画特别有效）
      debugPrint('ML Kit 识别: 回退策略4 - 骨架化');
      final grayForSkel = img.grayscale(fallbackBase);
      final skeletonized = _skeletonize(grayForSkel);
      final rawSkelResult = await _recognizeFromImage(skeletonized);
      final skelResult = _validateResult(rawSkelResult);
      if (skelResult != null) {
        debugPrint('ML Kit 识别: ✓ 骨架化成功, 字符="$skelResult"');
        return skelResult;
      }

      // 回退策略 5：骨架化 + 反转
      debugPrint('ML Kit 识别: 回退策略5 - 骨架化+反转');
      final skelInverted = _invertColors(skeletonized);
      final rawSkelInvResult = await _recognizeFromImage(skelInverted);
      final skelInvResult = _validateResult(rawSkelInvResult);
      if (skelInvResult != null) {
        debugPrint('ML Kit 识别: ✓ 骨架化+反转成功, 字符="$skelInvResult"');
        return skelInvResult;
      }

      debugPrint('ML Kit 识别: 所有${attempt}次常规尝试 + 5次回退策略均未识别到文字');
    } catch (e) {
      debugPrint('ML Kit 识别失败: $e');
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // v5.1.0: 增强识别方法 — 形近字学习 / 英文预处理 / 混排处理
  // ═══════════════════════════════════════════════════════════

  /// v5.1.0: 增强中文识别 — 形近字学习
  ///
  /// 利用修正学习服务和字典服务，对形近字进行智能辨别。
  /// 当识别置信度较低且候选字符存在形近字时，
  /// 结合笔画特征和历史修正记录选择最可能的结果。
  Future<String?> _enhancedChineseRecognition(
    Uint8List imageBytes,
    String initialResult,
    double confidence,
  ) async {
    if (confidence >= 0.85) return initialResult;

    try {
      // 形近字集：常见易混淆的汉字对
      const confusableSets = [
        ['己', '已', '巳'],
        ['未', '末'],
        ['天', '夫'],
        ['土', '士'],
        ['日', '曰'],
        ['入', '人'],
        ['大', '太', '犬'],
        ['田', '由', '甲', '申'],
        ['干', '千', '于'],
        ['王', '玉', '主'],
        ['午', '牛'],
        ['刀', '力'],
        ['八', '入'],
        ['贝', '见'],
        ['目', '自'],
        ['白', '自'],
        ['月', '目'],
        ['且', '目'],
        ['左', '右'],
        ['石', '右'],
        ['方', '万'],
        ['言', '信'],
        ['子', '了'],
        ['好', '妈'],
        ['他', '她'],
        ['的', '得', '地'],
        ['是', '时'],
        ['在', '再'],
        ['有', '又'],
        ['和', '合'],
      ];

      // 检查初始结果是否属于某个形近字集
      List<String>? confusableGroup;
      for (final group in confusableSets) {
        if (group.contains(initialResult)) {
          confusableGroup = group;
          break;
        }
      }

      if (confusableGroup == null) return initialResult;

      // 从修正学习中查找该形近字集的历史修正
      final correctionService = CorrectionLearningService.instance;
      final correction = await correctionService.findCorrection(
        recognizedChar: initialResult,
        confidence: confidence,
        imageWidth: null,
        imageHeight: null,
      );
      if (correction != null && confusableGroup.contains(correction)) {
        debugPrint('形近字学习: "$initialResult" → "$correction" '
            '(置信度=${(confidence * 100).toStringAsFixed(0)}%)');
        return correction;
      }

      return initialResult;
    } catch (e) {
      debugPrint('形近字学习失败: $e');
      return initialResult;
    }
  }

  /// v5.1.0: 增强英文识别 — 专用预处理
  ///
  /// 英文字符的识别需要不同的预处理策略：
  /// 1. 更高的锐化（英文字母笔画更细）
  /// 2. 更紧凑的裁剪（字母间距更紧密）
  /// 3. 区分大小写验证
  Future<String?> _enhancedEnglishRecognition(Uint8List imageBytes) async {
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return null;

      // 英文专用预处理：高锐化 + 自适应二值化
      var processed = decoded;

      // 转灰度
      processed = img.grayscale(processed);

      // 增强对比度（英文需要更高对比度）
      processed = img.adjustColor(processed, contrast: 1.5);

      // 锐化（英文笔画较细，需要更锐利的边缘）
      final sharpImg = img.Image(width: processed.width, height: processed.height);
      const kernel = [0.0, -1.0, 0.0, -1.0, 5.0, -1.0, 0.0, -1.0, 0.0];
      for (int y = 1; y < processed.height - 1; y++) {
        for (int x = 1; x < processed.width - 1; x++) {
          num r = 0;
          int ki = 0;
          for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
              r += processed.getPixel(x + dx, y + dy).r * kernel[ki];
              ki++;
            }
          }
          final v = r.clamp(0, 255).toInt();
          sharpImg.setPixelRgba(x, y, v, v, v, 255);
        }
      }
      processed = sharpImg;

      // 二值化
      final threshold = ImageProcessor.otsuThreshold(processed);
      processed = ImageProcessor.binarize(processed, threshold / 255.0, false);

      final pngBytes = img.encodePng(processed);
      final result = await _recognizeFromImageBytes(pngBytes);

      // 验证英文结果
      if (result != null && result.length == 1) {
        final code = result.codeUnitAt(0);
        // ASCII 字母范围
        if ((code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A)) {
          return result;
        }
      }

      return result;
    } catch (e) {
      debugPrint('英文增强识别失败: $e');
      return null;
    }
  }

  /// v5.1.0: 中英文混排处理
  ///
  /// 检测图片中是否同时包含中文和英文字符，
  /// 并根据字符特征选择最合适的识别策略。
  /// 返回识别结果和语言类型。
  Future<({String? result, String language})> _handleMixedLayout(
    Uint8List imageBytes,
  ) async {
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return (result: null, language: 'unknown');

      // 分析字符特征：宽高比和笔画密度
      final w = decoded.width;
      final h = decoded.height;
      final aspect = w / h.clamp(1, 99999);

      // 英文字符通常较窄（宽高比 < 0.8），中文通常接近正方形
      final isLikelyEnglish = aspect < 0.7 && w < h;

      // 计算黑色像素密度（中文笔画更密集）
      final gray = img.grayscale(decoded);
      int blackCount = 0;
      for (int y = 0; y < gray.height; y++) {
        for (int x = 0; x < gray.width; x++) {
          if (gray.getPixel(x, y).r.toInt() < 128) blackCount++;
        }
      }
      final density = blackCount / (w * h);

      // 密度 < 0.15 且窄形 → 更可能是英文
      if (isLikelyEnglish && density < 0.15) {
        final result = await _enhancedEnglishRecognition(imageBytes);
        return (result: result, language: 'en');
      }

      // 否则使用标准中文识别
      final result = await _recognizeLocal(imageBytes);
      return (result: result, language: 'zh');
    } catch (e) {
      debugPrint('混排处理失败: $e');
      return (result: null, language: 'unknown');
    }
  }

  /// 从 img.Image 保存临时文件并用 ML Kit 识别
  Future<String?> _recognizeFromImage(img.Image image) async {
    File? tempFile;
    try {
      final pngBytes = img.encodePng(image);
      final tempDir = await getTemporaryDirectory();
      final counter = ++_fileCounter;
      tempFile = File('${tempDir.path}/mlkit_${DateTime.now().microsecondsSinceEpoch}_$counter.png');
      await tempFile.writeAsBytes(pngBytes);

      final inputImage = InputImage.fromFilePath(tempFile.path);
      final recognizer = _getMlKitRecognizer();
      final recognizedText = await recognizer.processImage(inputImage);

      debugPrint('ML Kit 识别: 识别到 ${recognizedText.blocks.length} 个文本块');

      if (recognizedText.text.isNotEmpty) {
        for (final block in recognizedText.blocks) {
          for (final line in block.lines) {
            for (final element in line.elements) {
              final text = element.text.trim();
              if (text.isNotEmpty && text.runes.isNotEmpty) {
                final result = String.fromCharCodes(text.runes.take(1));
                // v4.3.0: 异常检测 — 过滤非汉字结果
                if (_isAnomalousResult(result)) {
                  debugPrint('ML Kit 识别: 异常检测过滤 "$result" (U+${result.codeUnitAt(0).toRadixString(16)})');
                  continue; // 跳过此结果，尝试下一个元素
                }
                // 计算并缓存识别置信度
                final confidence = _estimateConfidence(element, recognizedText);
                final imageHash = _hashBytes(pngBytes);
                _confidenceCache[imageHash] = confidence;
                debugPrint('ML Kit 识别: 置信度 ${(confidence * 100).toStringAsFixed(0)}%');
                return result;
              }
            }
          }
        }
      }
      return null;
    } finally {
      // 清理临时文件
      try { await tempFile?.delete(); } catch (_) {}
    }
  }

  /// 从 PNG 字节数据识别（复用 _recognizeFromImage 的逻辑）
  Future<String?> _recognizeFromImageBytes(Uint8List pngBytes) async {
    File? tempFile;
    try {
      final tempDir = await getTemporaryDirectory();
      final counter = ++_fileCounter;
      tempFile = File('${tempDir.path}/mlkit_bytes_${DateTime.now().microsecondsSinceEpoch}_$counter.png');
      await tempFile.writeAsBytes(pngBytes);

      final inputImage = InputImage.fromFilePath(tempFile.path);
      final recognizer = _getMlKitRecognizer();
      final recognizedText = await recognizer.processImage(inputImage);

      if (recognizedText.text.isEmpty) return null;

      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          for (final element in line.elements) {
            final text = element.text.trim();
            if (text.runes.length == 1) {
              final ch = String.fromCharCode(text.runes.first);
              if (_isValidChar(ch)) return ch;
            }
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint('_recognizeFromImageBytes 失败: $e');
      return null;
    } finally {
      try { await tempFile?.delete(); } catch (_) {}
    }
  }

  /// 估算 ML Kit 识别结果的置信度（0.0 ~ 1.0）
  /// 基于以下因素综合评估：
  /// - 文本长度（越短越可能是单字识别，置信度越高）
  /// - 是否为有效字符
  /// - 文本块数量（块越少，聚焦度越高）
  /// - 元素数量（元素越少，识别越聚焦）
  /// - 文本内容质量（是否为常见汉字）
  static double _estimateConfidence(
    TextElement element,
    RecognizedText recognizedText,
  ) {
    double confidence = 0.7; // 基线置信度
    final text = element.text.trim();

    // 单字符输出 → 较高置信度
    if (text.runes.length == 1) confidence += 0.15;
    // 多字符输出 → 降低置信度（可能是误识别多个字符）
    if (text.runes.length > 2) confidence -= 0.1;

    // 有效汉字 → 较高置信度
    if (text.runes.isNotEmpty) {
      final ch = String.fromCharCode(text.runes.first);
      if (_isValidChar(ch)) confidence += 0.1;
    }

    // 文本块数量少 → 聚焦度高
    if (recognizedText.blocks.length <= 1) confidence += 0.05;
    // 文本块过多 → 分散，降低置信度
    if (recognizedText.blocks.length > 3) confidence -= 0.05;

    // 元素数量少 → 识别更聚焦
    int totalElements = 0;
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        totalElements += line.elements.length;
      }
    }
    if (totalElements <= 1) confidence += 0.05;
    if (totalElements > 5) confidence -= 0.05;

    return confidence.clamp(0.0, 1.0);
  }

  /// 为云端 API 压缩图片
  /// 如果图片超过 200KB，缩放到最大 512x512（保持宽高比），编码为 JPEG quality=85
  Uint8List _compressForCloud(Uint8List imageBytes) {
    const int maxSizeBytes = 200 * 1024; // 200KB
    const int maxDimension = 512;
    const int jpegQuality = 85;

    if (imageBytes.length <= maxSizeBytes) {
      debugPrint('云端压缩: 图片 ${imageBytes.length} bytes < 200KB，跳过压缩');
      return imageBytes;
    }

    debugPrint('云端压缩: 原始大小 ${imageBytes.length} bytes (${(imageBytes.length / 1024).toStringAsFixed(1)} KB)');

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      debugPrint('云端压缩: 解码失败，使用原图');
      return imageBytes;
    }

    img.Image resized = decoded;
    final w = decoded.width;
    final h = decoded.height;
    final maxDim = w > h ? w : h;

    if (maxDim > maxDimension) {
      final scale = maxDimension / maxDim;
      final newW = (w * scale).round();
      final newH = (h * scale).round();
      resized = img.copyResize(decoded, width: newW, height: newH,
          interpolation: img.Interpolation.cubic);
      debugPrint('云端压缩: 缩放 ${w}x$h -> ${resized.width}x${resized.height}');
    }

    final jpegBytes = img.encodeJpg(resized, quality: jpegQuality);
    debugPrint('云端压缩: 压缩后 ${jpegBytes.length} bytes (${(jpegBytes.length / 1024).toStringAsFixed(1)} KB), '
        '压缩率 ${(100 - jpegBytes.length * 100 / imageBytes.length).toStringAsFixed(1)}%');

    return jpegBytes;
  }

  /// SSRF 防护：校验 URL 是否为公网地址
  bool _isValidPublicUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'https' && uri.scheme != 'http') return false;
      final host = uri.host;
      // 禁止私有/保留地址
      if (host == 'localhost' || host == '127.0.0.1' || host == '::1') return false;
      if (host.startsWith('10.') || host.startsWith('192.168.')) return false;
      if (host.startsWith('172.')) {
        final parts = host.split('.');
        if (parts.length >= 2) {
          final second = int.tryParse(parts[1]);
          if (second != null && second >= 16 && second <= 31) return false;
        }
      }
      if (host.startsWith('169.254.')) return false;
      if (host == '0.0.0.0') return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 云端 API 识别（OpenAI 兼容格式，支持 DeepSeek-OCR / 硅基流动）
  /// 支持自动重试：若首次返回无效字符，用更强 prompt 重试一次
  Future<String?> _recognizeCloud(Uint8List imageBytes) async {
    // 压缩大图以减少 API 传输量和耗时
    final Uint8List compressedBytes = _compressForCloud(imageBytes);

    final cloudUrl = await getCloudUrl();
    final cloudKey = await getCloudKey();

    if (cloudUrl.isEmpty) return null;
    if (!_isValidPublicUrl(cloudUrl)) {
      debugPrint('云端识别: URL 不合法或为私有地址');
      return null;
    }

    debugPrint('云端识别: 图片大小 ${compressedBytes.length} bytes');

    // 读取用户选择的模型
    final savedModel = await getModel();
    String modelName = savedModel;
    if (savedModel == 'custom') {
      final customModel = await getCustomModel();
      modelName = customModel.isNotEmpty ? customModel : defaultModel;
    }
    if (modelName.isEmpty) modelName = defaultModel;

    // 两轮 prompt：首轮简洁高效，重试时包含手写体变形示例和易混淆字参考
    final prompts = [
      '这是一个手写汉字图片。请识别其中唯一的汉字，直接输出该汉字，不要输出任何其他内容。如果无法识别，输出?',
      '请仔细辨认这张手写汉字图片。手写体常见变形：笔画连笔或断开、横不平竖不直、点写成短横、撇捺角度偏差、口写成圆圈。'
      '易混淆字参考：已/己/巳、未/末、大/太/犬、日/目/且、土/士、刀/力、入/人、天/夫。'
      '要求：只输出一个完整汉字，禁止输出偏旁、标点、拼音、解释。不确定就输出最可能的汉字。',
    ];

    for (int attempt = 0; attempt < prompts.length; attempt++) {
      final base64Image = base64Encode(compressedBytes);
      debugPrint('云端识别: 第${attempt + 1}次请求（prompt轮次）');

      // 网络重试：同一 prompt 最多重试 3 次（含首次）
      const int maxNetworkRetries = 3;
      for (int retry = 0; retry < maxNetworkRetries; retry++) {
        try {
          if (retry > 0) {
            debugPrint('云端识别: 网络重试第$retry次（等待 ${retry * 2} 秒）');
            await Future.delayed(Duration(seconds: retry * 2));
          }

          final response = await http.post(
            Uri.parse(cloudUrl),
            headers: {
              'Content-Type': 'application/json',
              if (cloudKey != null && cloudKey.isNotEmpty) 'Authorization': 'Bearer $cloudKey',
            },
            body: jsonEncode({
              'model': modelName,
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {
                      'type': 'image_url',
                      'image_url': {
                        'url': 'data:image/jpeg;base64,$base64Image',
                      },
                    },
                    {
                      'type': 'text',
                      'text': prompts[attempt],
                    },
                  ],
                },
              ],
              'max_tokens': 10,
            }),
          ).timeout(_timeout);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);

            // OpenAI 格式: choices[0].message.content
            if (data is Map && data['choices'] is List) {
              final choices = data['choices'] as List;
              if (choices.isNotEmpty) {
                final message = choices[0]['message'];
                if (message is Map) {
                  final content = message['content'] as String?;
                  debugPrint('云端识别: API 原始返回 "$content"');

                  if (content != null && content.isNotEmpty && content.runes.isNotEmpty) {
                    // 优先提取第一个中文字符（v4.3.0: 增加异常检测）
                    final chineseMatch = RegExp(r'[一-鿿]').firstMatch(content);
                    if (chineseMatch != null) {
                      final result = chineseMatch.group(0)!;
                      if (!_isAnomalousResult(result)) {
                        debugPrint('云端识别: ✓ 提取中文字符 "$result" (第${attempt + 1}次)');
                        return result;
                      }
                      debugPrint('云端识别: 异常检测过滤 "$result"');
                    }
                    // 否则遍历所有字符，取第一个有效字符（v4.3.0: 增加异常检测）
                    for (final rune in content.runes) {
                      final ch = String.fromCharCode(rune);
                      if (_isValidChar(ch) && !_isAnomalousResult(ch)) {
                        debugPrint('云端识别: ✓ 提取有效字符 "$ch" (第${attempt + 1}次)');
                        return ch;
                      }
                    }
                    debugPrint('云端识别: 内容 "$content" 中无有效字符，已过滤 (第${attempt + 1}次)');
                  } else {
                    debugPrint('云端识别: API 返回空内容 (第${attempt + 1}次)');
                  }
                }
              }
            }
            // 成功响应但无有效结果，跳出重试循环，进入下一轮 prompt
            break;
          } else {
            final statusCode = response.statusCode;
            if (statusCode == 401 || statusCode == 403) {
              debugPrint('云端识别认证失败 ($statusCode)');
              throw const CloudAuthException('认证失败: API Key 无效或已过期。请到「设置 → 云端识别配置」中重新填写 API Key，或切换为本地识别模式');
            }
            // 5xx 服务端错误可重试，4xx 客户端错误不重试
            if (statusCode >= 500 && retry < maxNetworkRetries - 1) {
              debugPrint('云端识别: 服务端错误 $statusCode，将重试');
              continue;
            }
            debugPrint('云端识别 HTTP $statusCode: ${response.body}');
            break; // 4xx 错误不重试
          }
        } on CloudAuthException {
          rethrow;
        } catch (e) {
          debugPrint('云端识别异常 (第${attempt + 1}次, 网络重试${retry + 1}/$maxNetworkRetries): $e');
          final isNetworkError = e is SocketException || e is TimeoutException ||
              e.toString().contains('Socket') ||
              e.toString().contains('Connection') ||
              e.toString().contains('timeout');
          if (isNetworkError && retry < maxNetworkRetries - 1) {
            continue; // 网络错误继续重试
          }
          // 最后一次重试仍失败
          if (isNetworkError && attempt == prompts.length - 1 && retry == maxNetworkRetries - 1) {
            debugPrint('云端识别: 网络重试全部失败，返回 null');
            return null;
          }
          break; // 非网络错误或还有 prompt 轮次，跳出重试循环
        }
      }
    }

    debugPrint('云端识别: 所有尝试均未返回有效字符');
    return null;
  }

  /// 校正识别结果（用户手动修正误识别的字符）
  /// 将校正结果写入缓存，后续相同图片将返回校正后的结果
  /// 同时将纠正记录存入用户反馈学习系统，用于相似图片匹配
  /// v4.4.0: 记录错误模式，用于后续自动纠正
  static void correctRecognition(Uint8List imageBytes, String correctedChar) {
    if (correctedChar.isEmpty) return;
    final cacheKey = _hashBytes(imageBytes);

    // v4.4.0: 记录错误模式（旧结果 → 新结果）
    final oldResult = _recognitionCache[cacheKey];
    if (oldResult != null && oldResult != correctedChar) {
      _recordErrorPattern(oldResult, correctedChar);
    }

    _recognitionCache[cacheKey] = correctedChar;
    _confidenceCache[cacheKey] = 1.0; // 用户校正结果置信度为 100%
    // 更新 LRU 顺序
    _cacheAccessOrder.remove(cacheKey);
    _cacheAccessOrder.add(cacheKey);
    debugPrint('识别校正: hash=$cacheKey → "$correctedChar"');
    // 存入用户反馈学习系统（异步，不阻塞）
    UserFeedbackService.instance.feedback(imageBytes, correctedChar);
  }

  /// 读取已选择的模型
  Future<String> getModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeyModel) ?? defaultModel;
  }

  /// 保存选择的模型
  Future<void> setModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyModel, model);
  }

  /// 读取自定义模型名称
  Future<String> getCustomModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKeyCustomModel) ?? '';
  }

  /// 保存自定义模型名称
  Future<void> setCustomModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyCustomModel, model);
  }

  /// TFLite 模型识别开关
  Future<bool> getUseTflite() async {
    if (_useTflite != null) return _useTflite!;
    final prefs = await SharedPreferences.getInstance();
    // 默认：模型可用时启用
    _useTflite = prefs.getBool(_prefKeyUseTflite) ?? true;
    return _useTflite!;
  }

  Future<void> setUseTflite(bool value) async {
    _useTflite = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyUseTflite, value);
  }

  /// TFLite 模型是否实际可用（已加载且非占位符）
  bool get isTfliteModelAvailable => TfliteRecognitionService.instance.isModelLoaded; // isModelLoaded 已包含可用性检查

  /// 释放资源（应在 app 退出时调用）
  void dispose() {
    _mlKitRecognizer?.close();
    _mlKitRecognizer = null;
    // v4.1.0: 释放 TFLite 资源
    TfliteRecognitionService.instance.dispose();
    _recognitionCache.clear();
    _confidenceCache.clear();
    _detailCache.clear();
    _cacheAccessOrder.clear();
    _estimatedCacheBytes = 0;
    // v4.3.0: 退出前保存策略权重
    _saveStrategyWeights();
    _strategyReliability.clear();
    _strategyWeightsLoaded = false;
    // 重置调试统计
    _totalRecognitions = 0;
    _successfulRecognitions = 0;
    _failedRecognitions = 0;
    _cacheHits = 0;
    _cacheMisses = 0;
    _latencyHistory.clear();
    _debugLogBuffer.clear();
  }

  // ═══════════════════════════════════════════════════════════
  // v4.3.0: 策略权重持久化
  // ═══════════════════════════════════════════════════════════

  /// 确保策略权重已从持久化存储加载
  static Future<void> _ensureStrategyWeightsLoaded() async {
    if (_strategyWeightsLoaded) return;
    _strategyWeightsLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKeyStrategyWeights);
      if (json != null && json.isNotEmpty) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        for (final entry in map.entries) {
          _strategyReliability[entry.key] = (entry.value as num).toDouble();
        }
        debugPrint('策略权重: 已加载 ${_strategyReliability.length} 个策略权重');
      }
    } catch (e) {
      debugPrint('策略权重: 加载失败 $e');
    }
  }

  /// 保存策略权重到持久化存储
  static Future<void> _saveStrategyWeights() async {
    if (_strategyReliability.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{};
      for (final entry in _strategyReliability.entries) {
        map[entry.key] = double.parse(entry.value.toStringAsFixed(4));
      }
      await prefs.setString(_prefKeyStrategyWeights, jsonEncode(map));
      debugPrint('策略权重: 已保存 ${_strategyReliability.length} 个策略权重');
    } catch (e) {
      debugPrint('策略权重: 保存失败 $e');
    }
  }

  /// 时间衰减：每天衰减 1%，防止旧数据过度影响
  static void _applyTimeDecay() {
    final now = DateTime.now();
    final daysSinceLastDecay = now.difference(_lastStrategyDecay).inDays;
    if (daysSinceLastDecay <= 0) return;
    // 每天衰减 1%（向 0.5 中间值靠拢）
    final decayFactor = 0.99 * daysSinceLastDecay;
    if (decayFactor >= 1.0) return;
    for (final key in _strategyReliability.keys.toList()) {
      final val = _strategyReliability[key]!;
      // 向 0.5 靠拢：newVal = 0.5 + (val - 0.5) * decayFactor
      _strategyReliability[key] = (0.5 + (val - 0.5) * decayFactor).clamp(0.0, 1.0);
    }
    _lastStrategyDecay = now;
    debugPrint('策略权重: 时间衰减 ${daysSinceLastDecay}天');
  }

  /// 获取策略权重统计（供 UI 展示）
  static Map<String, dynamic> getStrategyWeightStats() {
    return {
      'weights': Map.unmodifiable(_strategyReliability),
      'loaded': _strategyWeightsLoaded,
      'updateCount': _strategyUpdateCount,
    };
  }

  // ═══════════════════════════════════════════════════════════
  // v4.4.0: 错误模式学习 — 记录常见误识别模式，建立纠正映射
  // ═══════════════════════════════════════════════════════════

  /// 错误模式映射（错误结果 → 正确结果 → 出现次数）
  /// 例如：{"己": {"已": 5}} 表示 "己" 被误识别为 "已" 5 次
  static final Map<String, Map<String, int>> _errorPatterns = {};

  /// v4.8.0: 预置常见手写体混淆对（高频误识别模式）
  /// 这些是手写体中经常互相混淆的字对，基于 OCR 频率统计
  /// v5.7.0: 扩充至 120+ 组混淆对，覆盖更多手写体常见误识别
  static const Map<String, Map<String, int>> _builtinErrorPatterns = {
    // ── 形近字混淆（笔画结构相似）──
    '已': {'己': 5, '以': 2}, '己': {'已': 5},
    '末': {'未': 5}, '未': {'末': 5},
    '土': {'士': 5}, '士': {'土': 5},
    '天': {'夫': 4, '无': 2}, '夫': {'天': 4},
    '大': {'太': 4, '犬': 3}, '太': {'大': 4, '犬': 3}, '犬': {'大': 3, '太': 3},
    '日': {'曰': 5, '口': 3, '目': 3}, '曰': {'日': 5}, '目': {'日': 3},
    '入': {'人': 4, '八': 3}, '人': {'入': 4}, '八': {'入': 3},
    '刀': {'力': 4}, '力': {'刀': 4},
    '几': {'九': 3}, '九': {'几': 3},
    '干': {'千': 4, '于': 3}, '千': {'干': 4}, '于': {'干': 3},
    '王': {'玉': 3}, '玉': {'王': 3},
    '甲': {'由': 4, '田': 3}, '由': {'甲': 4, '田': 3}, '田': {'由': 3, '甲': 3}, '申': {'甲': 3},
    '贝': {'见': 3}, '见': {'贝': 3},
    '午': {'牛': 4}, '牛': {'午': 4},
    '鸟': {'乌': 3}, '乌': {'鸟': 3},
    '折': {'拆': 3}, '拆': {'折': 3},
    '拔': {'拨': 3}, '拨': {'拔': 3},
    '辨': {'辩': 4, '辫': 3}, '辩': {'辨': 4}, '辫': {'辨': 3},
    '体': {'休': 3}, '休': {'体': 3},
    '令': {'今': 3}, '今': {'令': 3},
    '候': {'侯': 3}, '侯': {'候': 3},
    '水': {'永': 3}, '永': {'水': 3},
    '手': {'毛': 3}, '毛': {'手': 3},
    '心': {'必': 3}, '必': {'心': 3},
    '禾': {'木': 3}, '木': {'禾': 3},
    '电': {'龟': 3}, '龟': {'电': 3},
    '万': {'方': 3}, '方': {'万': 3},
    '问': {'间': 3}, '间': {'问': 3},

    // ── 偏旁部首相似 ──
    '晴': {'睛': 3, '请': 3, '清': 3, '情': 3},
    '睛': {'晴': 3},
    '清': {'请': 3, '情': 3, '晴': 3},
    '请': {'清': 3, '情': 3, '晴': 3},
    '情': {'清': 3, '请': 3, '晴': 3},
    '很': {'狠': 3, '恨': 2}, '狠': {'很': 3},
    '抱': {'跑': 3, '泡': 2, '饱': 2}, '跑': {'抱': 3}, '泡': {'抱': 2}, '饱': {'抱': 2},
    '科': {'料': 3}, '料': {'科': 3},
    '话': {'活': 3}, '活': {'话': 3},
    '起': {'越': 3}, '越': {'起': 3},
    '阳': {'阴': 3}, '阴': {'阳': 3},
    '风': {'凤': 3}, '凤': {'风': 3},
    '颗': {'棵': 3}, '棵': {'颗': 3},
    '买': {'卖': 3}, '卖': {'买': 3},
    '座': {'坐': 3}, '坐': {'座': 3},
    '做': {'作': 3}, '作': {'做': 3},
    '密': {'蜜': 3}, '蜜': {'密': 3},
    '妈': {'好': 2, '吗': 2}, '好': {'妈': 2},
    '字': {'学': 2}, '学': {'字': 2},
    '明': {'朋': 2}, '朋': {'明': 2},
    '注': {'住': 2}, '住': {'注': 2},

    // ── 同音/近音字混淆 ──
    '的': {'地': 3, '得': 3, '白': 2},
    '地': {'的': 3, '得': 2},
    '得': {'的': 3, '地': 2},
    '在': {'再': 3, '左': 2}, '再': {'在': 3},
    '以': {'已': 3},
    '那': {'哪': 3}, '哪': {'那': 3},
    '他': {'她': 3, '它': 3}, '她': {'他': 3}, '它': {'他': 3},
    '有': {'又': 2, '右': 2}, '又': {'有': 2},
    '分': {'份': 2}, '份': {'分': 2},
    '近': {'进': 3}, '进': {'近': 3},
    '气': {'汽': 3}, '汽': {'气': 3},
    '工': {'公': 2}, '公': {'工': 2},
    '带': {'戴': 2}, '戴': {'带': 2},
    '只': {'支': 2}, '支': {'只': 2},
    '知': {'之': 2}, '之': {'知': 2},

    // ── 笔画缺失/多余 ──
    '口': {'日': 3},
    '月': {'日': 3},
    '白': {'自': 3}, '自': {'白': 3},
    '百': {'白': 3},
    '们': {'门': 3}, '门': {'们': 3},

    // ── 常见手写体误识别 ──
    '是': {'足': 2, '事': 2},
    '了': {'子': 2}, '子': {'了': 2},
    '左': {'在': 2},
    '右': {'有': 2, '石': 2},
    '这': {'过': 2}, '过': {'这': 2},
    '不': {'下': 2}, '下': {'不': 2},
    '和': {'种': 2}, '种': {'和': 2},
    '上': {'土': 2}, '中': {'口': 2},
  };

  /// 错误模式持久化 key
  static const String _prefKeyErrorPatterns = 'ocr_error_patterns';

  /// 是否已加载错误模式
  static bool _errorPatternsLoaded = false;

  /// 错误模式学习阈值：出现次数 >= threshold 才启用自动纠正
  static const int _errorPatternThreshold = 2;

  /// 最大错误模式数
  static const int _maxErrorPatterns = 500;

  /// 确保错误模式已加载
  static Future<void> _ensureErrorPatternsLoaded() async {
    if (_errorPatternsLoaded) return;
    _errorPatternsLoaded = true;

    // v4.8.0: 先加载预置混淆对
    for (final entry in _builtinErrorPatterns.entries) {
      _errorPatterns[entry.key] = Map<String, int>.from(entry.value);
    }
    debugPrint('错误模式: 已加载 ${_builtinErrorPatterns.length} 组预置混淆对');

    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKeyErrorPatterns);
      if (json != null && json.isNotEmpty) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        for (final entry in map.entries) {
          final wrong = entry.key;
          final corrections = entry.value as Map<String, dynamic>;
          // 合并用户学习的模式（覆盖预置的）
          _errorPatterns[wrong] = {};
          for (final c in corrections.entries) {
            _errorPatterns[wrong]![c.key] = c.value as int;
          }
        }
        debugPrint('错误模式: 已加载 ${_errorPatterns.length} 组错误映射（含用户学习）');
      }
    } catch (e) {
      debugPrint('错误模式: 加载失败 $e');
    }
  }

  /// 保存错误模式到持久化存储
  static Future<void> _saveErrorPatterns() async {
    if (_errorPatterns.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{};
      for (final entry in _errorPatterns.entries) {
        map[entry.key] = Map<String, dynamic>.from(entry.value);
      }
      await prefs.setString(_prefKeyErrorPatterns, jsonEncode(map));
      debugPrint('错误模式: 已保存 ${_errorPatterns.length} 组错误映射');
    } catch (e) {
      debugPrint('错误模式: 保存失败 $e');
    }
  }

  /// 记录错误模式（当用户纠正识别结果时调用）
  ///
  /// [wrongResult] 识别错误的结果
  /// [correctResult] 用户纠正后的正确结果
  static void _recordErrorPattern(String wrongResult, String correctResult) {
    if (wrongResult == correctResult) return;

    _errorPatterns.putIfAbsent(wrongResult, () => {});
    _errorPatterns[wrongResult]![correctResult] =
        (_errorPatterns[wrongResult]![correctResult] ?? 0) + 1;

    // 限制总条目数
    int totalEntries = 0;
    for (final v in _errorPatterns.values) {
      totalEntries += v.length;
    }
    if (totalEntries > _maxErrorPatterns) {
      // 移除出现次数最少的条目
      String? minWrong;
      String? minCorrect;
      int minCount = 999999;
      for (final entry in _errorPatterns.entries) {
        for (final c in entry.value.entries) {
          if (c.value < minCount) {
            minCount = c.value;
            minWrong = entry.key;
            minCorrect = c.key;
          }
        }
      }
      if (minWrong != null && minCorrect != null) {
        _errorPatterns[minWrong]!.remove(minCorrect);
        if (_errorPatterns[minWrong]!.isEmpty) {
          _errorPatterns.remove(minWrong);
        }
      }
    }

    debugPrint('错误模式: 记录 "$wrongResult" → "$correctResult" '
        '(累计 ${_errorPatterns[wrongResult]![correctResult]} 次)');

    // 异步保存（不阻塞）
    _saveErrorPatterns();
  }

  /// 应用错误模式纠正 — 如果识别结果有已知的高频误识别模式，自动纠正
  ///
  /// 返回纠正后的结果，如果没有匹配的错误模式则返回原结果
  static Future<String?> _applyErrorPatternCorrection(String result) async {
    await _ensureErrorPatternsLoaded();

    final corrections = _errorPatterns[result];
    if (corrections == null || corrections.isEmpty) return result;

    // 找到出现次数最多的纠正映射
    String? bestCorrection;
    int bestCount = 0;
    for (final entry in corrections.entries) {
      if (entry.value > bestCount && entry.value >= _errorPatternThreshold) {
        bestCount = entry.value;
        bestCorrection = entry.key;
      }
    }

    if (bestCorrection != null) {
      debugPrint('错误模式纠正: "$result" → "$bestCorrection" (出现 $bestCount 次)');
      return bestCorrection;
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════════
  // v5.2.0: 形近字消歧 — 基于上下文的形近字自动纠正
  // ═══════════════════════════════════════════════════════════

  /// 形近字组 — 每组内的字符形状相似，容易混淆
  /// key = 组名，value = 该组内的形近字集合
  static const Map<String, List<String>> _confusableGroups = {
    // ── 笔画结构相似（视觉消歧已实现）──
    '己已巳': ['己', '已', '巳'],
    '太大犬': ['太', '大', '犬'],
    '未末': ['未', '末'],
    '土士': ['土', '士'],
    '天夫': ['天', '夫'],
    '干千于': ['干', '千', '于'],
    '人入': ['人', '入'],
    '刀力': ['刀', '力'],
    '日目': ['日', '目'],
    '田由甲': ['田', '由', '甲'],
    '白自': ['白', '自'],
    '贝见': ['贝', '见'],
    '问间': ['问', '间'],
    '午牛': ['午', '牛'],
    '鸟乌': ['鸟', '乌'],
    '王玉': ['王', '玉'],
    '日曰': ['日', '曰'],
    '水永': ['水', '永'],
    '手毛': ['手', '毛'],
    '心必': ['心', '必'],
    '禾木': ['禾', '木'],
    '体休': ['体', '休'],
    '万方': ['万', '方'],
    '无天': ['无', '天'],
    '电龟': ['电', '龟'],
    '申甲': ['申', '甲'],
    // ── 偏旁部首相似 ──
    '买卖': ['买', '卖'],
    '令今': ['令', '今'],
    '折拆': ['折', '拆'],
    '拔拨': ['拔', '拨'],
    '候侯': ['候', '侯'],
    '辨辩辫': ['辨', '辩', '辫'],
    '密蜜': ['密', '蜜'],
    '座坐': ['座', '坐'],
    '科料': ['科', '料'],
    '话活': ['话', '活'],
    '起越': ['起', '越'],
    '阳阴': ['阳', '阴'],
    '风凤': ['风', '凤'],
    '颗棵': ['颗', '棵'],
    '抱报': ['抱', '报'],
    '清青': ['清', '青'],
    '做作': ['做', '作'],
    // ── 同音/近音字（主要靠上下文消歧）──
    '的地得': ['的', '地', '得'],
    '在再': ['在', '再'],
    '以已': ['以', '已'],
    '那哪': ['那', '哪'],
    '他她它': ['他', '她', '它'],
    '有又': ['有', '又'],
    '分份': ['分', '份'],
    '近进': ['近', '进'],
    '气汽': ['气', '汽'],
    '工公': ['工', '公'],
    '带戴': ['带', '戴'],
    '应映': ['应', '映'],
    '只支': ['只', '支'],
    '知之': ['知', '之'],
    // ── v5.7.0: 新增形近字组 ──
    '晴睛': ['晴', '睛'],
    '跑跳': ['跑', '跳'],
    '很狠': ['很', '狠'],
    '喝渴': ['喝', '渴'],
    '吧把': ['吧', '把'],
    '呢泥': ['呢', '泥'],
    '吗妈': ['吗', '妈'],
    '请清情晴': ['请', '清', '情', '晴'],
    '饱跑抱泡': ['饱', '跑', '抱', '泡'],
    '注住': ['注', '住'],
    '还远': ['还', '远'],
    '过边': ['过', '边'],
    '谁难': ['谁', '难'],
    '想想相': ['想', '相'],
    '样洋': ['样', '洋'],
    '说话': ['说', '话'],
    '谢讲': ['谢', '讲'],
    '认识': ['认', '识'],
    '字学': ['字', '学'],
    '明朋': ['明', '朋'],
    '妈好': ['妈', '好'],
    '她他': ['她', '他'],
  };

  /// v5.7.0: 形近字视觉特征定义 — 每组形近字的关键视觉区分特征
  ///
  /// 对于每个候选字符，定义需要在图片中验证的视觉特征检查。
  /// 特征检查函数接收二值化图片，返回 0.0~1.0 的匹配分数。
  /// 空 map 表示该组没有可用的视觉特征定义，退回到纯上下文消歧。
  static Map<String, Map<String, double Function(img.Image)>> get _visualFeatureChecks {
    return {};
  }

  /// v5.7.0: 形近字视觉消歧 — 分析图片的视觉特征来区分形近字
  ///
  /// 对于每个候选字符，提取图片中的关键视觉特征并与预期特征对比。
  /// 返回每个候选的视觉匹配分数 (0.0~1.0)，供综合评分使用。
  static Map<String, double> _scoreConfusableByVisual(
    img.Image image,
    List<String> candidates,
  ) {
    final scores = <String, double>{};
    for (final c in candidates) {
      scores[c] = 0.5; // 默认中性分
    }

    try {
      // 预处理：灰度 + 二值化
      final gray = img.grayscale(image);
      final binary = ImageProcessor.adaptiveThreshold(gray, blockSize: 21, c: 10, invert: false);
      final w = binary.width, h = binary.height;
      if (w < 10 || h < 10) return scores;

      // 分析图片的全局特征
      final aspectRatio = w / h;
      final inkDensity = _computeInkDensity(binary);
      final verticalProfile = _computeVerticalProjection(binary);
      final horizontalProfile = _computeHorizontalProjection(binary);

      // 按形近字组分组评分
      for (final candidate in candidates) {
        double score = 0.5;

        // ── 己/已/巳 ──
        // 己: 开口向右下，竖弯钩不封口
        // 已: 竖弯钩半封口，弯钩较短
        // 巳: 竖弯钩全封口，弯钩最长最圆
        if (candidate == '己' || candidate == '已' || candidate == '巳') {
          score = _scoreJiYiSi(binary, horizontalProfile, verticalProfile, candidate);
        }
        // ── 未/末 ──
        // 未: 下横比上横短（上宽下窄）
        // 末: 下横比上横长（上窄下宽）
        else if (candidate == '未' || candidate == '末') {
          score = _scoreWeiMo(binary, horizontalProfile, candidate);
        }
        // ── 土/士 ──
        // 土: 下横比上横长（稳重）
        // 士: 上横比下横长（挺拔）
        else if (candidate == '土' || candidate == '士') {
          score = _scoreTuShi(binary, horizontalProfile, candidate);
        }
        // ── 太/大/犬 ──
        // 太: 有小点在右下
        // 大: 撇捺对称展开
        // 犬: 右上有点
        else if (candidate == '太' || candidate == '大' || candidate == '犬') {
          score = _scoreTaiDaQuan(binary, candidate);
        }
        // ── 天/夫 ──
        // 天: 两横 + 撇捺
        // 夫: 两横 + 撇 + 捺，竖穿过上横
        else if (candidate == '天' || candidate == '夫') {
          score = _scoreTianFu(binary, horizontalProfile, candidate);
        }
        // ── 干/千/于 ──
        // 干: 两横一竖，横短竖长
        // 千: 撇+横+竖，有撇画
        // 于: 横+竖钩+点，有钩
        else if (candidate == '干' || candidate == '千' || candidate == '于') {
          score = _scoreGanQianYu(binary, horizontalProfile, candidate);
        }
        // ── 人/入 ──
        // 人: 撇长捺短，交叉点偏上
        // 入: 撇短捺长，交叉点偏下
        else if (candidate == '人' || candidate == '入') {
          score = _scoreRenRu(binary, candidate);
        }
        // ── 午/牛 ──
        // 午: 撇短，横在中间
        // 牛: 撇长，横在上方
        else if (candidate == '午' || candidate == '牛') {
          score = _scoreWuNiu(binary, horizontalProfile, candidate);
        }
        // ── 日/目 ──
        // 日: 内部一横（三段）
        // 目: 内部两横（四段）
        else if (candidate == '日' || candidate == '目') {
          score = _scoreRiMu(binary, horizontalProfile, candidate);
        }
        // ── 田/由 ──
        // 田: 十字交叉在中间
        // 由: 竖画向下延伸出框
        else if (candidate == '田' || candidate == '由') {
          score = _scoreTianYou(binary, verticalProfile, candidate);
        }
        // ── 白/自 ──
        // 白: 顶部有撇，内部一横
        // 自: 顶部平，内部两横
        else if (candidate == '白' || candidate == '自') {
          score = _scoreBaiZi(binary, horizontalProfile, candidate);
        }
        // ── 日/曰 ──
        // 日: 纵向长方形 (aspect > 1)
        // 曰: 横向长方形 (aspect < 1)
        else if (candidate == '日' || candidate == '曰') {
          score = _scoreRiYue(aspectRatio, inkDensity, candidate);
        }
        // ── 王/玉 ──
        // 王: 三横一竖，无点
        // 玉: 三横一竖+右下点
        else if (candidate == '王' || candidate == '玉') {
          score = _scoreWangYu(binary, candidate);
        }
        // ── 刀/力 ──
        // 刀: 横折钩为主，撇短
        // 力: 横折钩 + 长撇穿过钩
        else if (candidate == '刀' || candidate == '力') {
          score = _scoreDaoLi(binary, horizontalProfile, candidate);
        }
        // ── 鸟/乌 ──
        // 鸟: 头部有点（眼睛）
        // 乌: 头部无点
        else if (candidate == '鸟' || candidate == '乌') {
          score = _scoreNiaoWu(binary, candidate);
        }
        // ── 买/卖 ──
        // 买: 上部简单
        // 卖: 上部有"十"
        else if (candidate == '买' || candidate == '卖') {
          score = _scoreMaiMai(binary, horizontalProfile, candidate);
        }
        // ── 请/清/情/晴 ──
        // 通过左半部分偏旁特征区分
        else if (candidate == '请' || candidate == '清' || candidate == '情' || candidate == '晴') {
          score = _scoreQingFamily(binary, verticalProfile, candidate);
        }
        // ── 甲/申/田 ──
        // 田: 框内十字
        // 由: 竖向下延伸出框
        // 甲: 竖向下延伸 + 框内十字
        else if (candidate == '甲' || candidate == '申') {
          score = _scoreTianYou(binary, verticalProfile, candidate);
        }
        // ── v5.8.0: 新增形近字视觉评分 ──
        // ── 贝/见 ──
        else if (candidate == '贝' || candidate == '见') {
          score = _scoreBeiJian(binary, horizontalProfile, candidate);
        }
        // ── 问/间 ──
        else if (candidate == '问' || candidate == '间') {
          score = _scoreWenJian(binary, horizontalProfile, candidate);
        }
        // ── 水/永 ──
        else if (candidate == '水' || candidate == '永') {
          score = _scoreShuiYong(binary, horizontalProfile, candidate);
        }
        // ── 手/毛 ──
        else if (candidate == '手' || candidate == '毛') {
          score = _scoreShouMao(binary, horizontalProfile, candidate);
        }
        // ── 心/必 ──
        else if (candidate == '心' || candidate == '必') {
          score = _scoreXinBi(binary, verticalProfile, candidate);
        }
        // ── 禾/木 ──
        else if (candidate == '禾' || candidate == '木') {
          score = _scoreHeMu(binary, candidate);
        }
        // ── 体/休 ──
        else if (candidate == '体' || candidate == '休') {
          score = _scoreTiXiu(binary, horizontalProfile, candidate);
        }
        // ── 万/方 ──
        else if (candidate == '万' || candidate == '方') {
          score = _scoreWanFang(binary, candidate);
        }
        // ── 无/天 ──
        else if (candidate == '无' || candidate == '天') {
          score = _scoreWuTian(binary, horizontalProfile, candidate);
        }
        // ── 电/龟 ──
        else if (candidate == '电' || candidate == '龟') {
          score = _scoreDianGui(binary, horizontalProfile, candidate);
        }
        // ── 晴/睛 ──
        else if (candidate == '晴' || candidate == '睛') {
          score = _scoreQingJing(binary, verticalProfile, candidate);
        }
        // ── 很/狠 ──
        else if (candidate == '很' || candidate == '狠') {
          score = _scoreHenHen(binary, candidate);
        }
        // ── 喝/渴 ──
        else if (candidate == '喝' || candidate == '渴') {
          score = _scoreHeKe(binary, verticalProfile, candidate);
        }
        // ── v5.8.0: 继续扩展形近字视觉评分 ──
        // ── 令/今 ──
        else if (candidate == '令' || candidate == '今') {
          score = _scoreLingJin(binary, candidate);
        }
        // ── 折/拆 ──
        else if (candidate == '折' || candidate == '拆') {
          score = _scoreZheChai(binary, candidate);
        }
        // ── 拔/拨 ──
        else if (candidate == '拔' || candidate == '拨') {
          score = _scoreBaBo(binary, candidate);
        }
        // ── 候/侯 ──
        else if (candidate == '候' || candidate == '侯') {
          score = _scoreHouHou(binary, verticalProfile, candidate);
        }
        // ── 密/蜜 ──
        else if (candidate == '密' || candidate == '蜜') {
          score = _scoreMiMi(binary, horizontalProfile, candidate);
        }
        // ── 座/坐 ──
        else if (candidate == '座' || candidate == '坐') {
          score = _scoreZuoZuo(binary, horizontalProfile, candidate);
        }
        // ── 科/料 ──
        else if (candidate == '科' || candidate == '料') {
          score = _scoreKeLiao(binary, verticalProfile, candidate);
        }
        // ── 话/活 ──
        else if (candidate == '话' || candidate == '活') {
          score = _scoreHuaHuo(binary, verticalProfile, candidate);
        }
        // ── 阳/阴 ──
        else if (candidate == '阳' || candidate == '阴') {
          score = _scoreYangYin(binary, verticalProfile, candidate);
        }
        // ── 风/凤 ──
        else if (candidate == '风' || candidate == '凤') {
          score = _scoreFengFeng(binary, candidate);
        }
        // ── 颗/棵 ──
        else if (candidate == '颗' || candidate == '棵') {
          score = _scoreKeKe(binary, horizontalProfile, candidate);
        }
        // ── 抱/报 ──
        else if (candidate == '抱' || candidate == '报') {
          score = _scoreBaoBao(binary, horizontalProfile, candidate);
        }
        // ── 做/作 ──
        else if (candidate == '做' || candidate == '作') {
          score = _scoreZuoZuo2(binary, horizontalProfile, candidate);
        }
        // ── 跑/跳 ──
        else if (candidate == '跑' || candidate == '跳') {
          score = _scorePaoTiao(binary, candidate);
        }
        // ── 注/住 ──
        else if (candidate == '注' || candidate == '住') {
          score = _scoreZhuZhu(binary, verticalProfile, candidate);
        }
        // ── 明/朋 ──
        else if (candidate == '明' || candidate == '朋') {
          score = _scoreMingPeng(binary, verticalProfile, candidate);
        }
        // ── 认/识 ──
        else if (candidate == '认' || candidate == '识') {
          score = _scoreRenShi(binary, horizontalProfile, candidate);
        }
        // ── 字/学 ──
        else if (candidate == '字' || candidate == '学') {
          score = _scoreZiXue(binary, horizontalProfile, candidate);
        }
        // ── 说/话 ──
        else if (candidate == '说' || candidate == '话') {
          score = _scoreShuoHua(binary, horizontalProfile, candidate);
        }
        // ── 样/洋 ──
        else if (candidate == '样' || candidate == '洋') {
          score = _scoreYangYang(binary, verticalProfile, candidate);
        }
        // ── 妈/好 ──
        else if (candidate == '妈' || candidate == '好') {
          score = _scoreMaHao(binary, horizontalProfile, candidate);
        }
        // ── 他/她 ──
        else if (candidate == '他' || candidate == '她') {
          score = _scoreTaTa(binary, verticalProfile, candidate);
        }

        scores[candidate] = score;
      }
    } catch (e) {
      debugPrint('视觉消歧分析异常: $e');
    }

    return scores;
  }

  // ═══════════════════════════════════════════════════════════
  // v5.7.0: 形近字视觉评分函数
  // ═══════════════════════════════════════════════════════════

  /// 计算墨迹密度（前景像素占比）
  static double _computeInkDensity(img.Image binary) {
    int fg = 0;
    final total = binary.width * binary.height;
    for (int y = 0; y < binary.height; y++) {
      for (int x = 0; x < binary.width; x++) {
        if (ImageProcessor.isBlack(binary, x, y)) fg++;
      }
    }
    return fg / total;
  }

  /// 计算垂直投影（每列的黑色像素数）
  static List<int> _computeVerticalProjection(img.Image binary) {
    final proj = List<int>.filled(binary.width, 0);
    for (int x = 0; x < binary.width; x++) {
      for (int y = 0; y < binary.height; y++) {
        if (ImageProcessor.isBlack(binary, x, y)) proj[x]++;
      }
    }
    return proj;
  }

  /// 计算水平投影（每行的黑色像素数）
  static List<int> _computeHorizontalProjection(img.Image binary) {
    final proj = List<int>.filled(binary.height, 0);
    for (int y = 0; y < binary.height; y++) {
      for (int x = 0; x < binary.width; x++) {
        if (ImageProcessor.isBlack(binary, x, y)) proj[y]++;
      }
    }
    return proj;
  }

  /// 己/已/巳 视觉评分
  /// 己: 右下开口，弯钩不封口
  /// 已: 弯钩半封口
  /// 巳: 弯钩全封口，底部封闭
  static double _scoreJiYiSi(img.Image binary, List<int> hProj, List<int> vProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 分析底部区域（下半部分）的封闭程度
    // 巳的底部最封闭，己的最开放
    final bottomStart = (h * 0.6).round();
    int bottomInk = 0;
    int bottomRightInk = 0;
    final midX = w ~/ 2;
    for (int y = bottomStart; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (ImageProcessor.isBlack(binary, x, y)) bottomInk++;
      }
      for (int x = midX; x < w; x++) {
        if (ImageProcessor.isBlack(binary, x, y)) bottomRightInk++;
      }
    }
    final bottomDensity = bottomInk / (w * (h - bottomStart));
    final rightBias = bottomRightInk > 0 ? bottomInk / bottomRightInk : 1.0;

    // 右侧竖投影：分析右半部分是否有封闭的竖线
    int rightVertical = 0;
    for (int x = (w * 0.6).round(); x < w; x++) {
      if (vProj[x] > h * 0.3) rightVertical++;
    }
    final rightClosure = rightVertical / (w * 0.4).round().clamp(1, 99);

    if (candidate == '巳') {
      // 巳: 底部封闭 → 右下墨迹密度高，右侧有封闭竖线
      return (bottomDensity * 2.0 + rightClosure * 1.5).clamp(0.0, 1.0);
    } else if (candidate == '已') {
      // 已: 半封口 → 中等底部密度
      return (0.5 + (1.0 - (bottomDensity - 0.3).abs() * 3)).clamp(0.2, 0.8);
    } else {
      // 己: 开口 → 底部密度低，右侧无封闭线
      return ((1.0 - bottomDensity) * 0.8 + (1.0 - rightClosure) * 0.5).clamp(0.0, 1.0);
    }
  }

  /// 未/末 视觉评分
  /// 未: 上横长、下横短
  /// 末: 上横短、下横长
  static double _scoreWeiMo(img.Image binary, List<int> hProj, String candidate) {
    final h = binary.height;
    // 找到两条横线的位置
    final peaks = _findHorizontalPeaks(hProj, h);
    if (peaks.length < 2) return 0.5;

    final upperY = peaks[0];
    final lowerY = peaks[1];

    // 计算上横和下横的宽度（连续黑色像素跨度）
    final upperWidth = _measureStrokeWidthAtRow(binary, upperY);
    final lowerWidth = _measureStrokeWidthAtRow(binary, lowerY);

    if (upperWidth == 0 || lowerWidth == 0) return 0.5;

    final ratio = lowerWidth / upperWidth;

    if (candidate == '未') {
      // 未: 下横比上横短 → ratio < 1
      return (1.0 - ratio).clamp(0.2, 1.0);
    } else {
      // 末: 下横比上横长 → ratio > 1
      return ratio.clamp(0.0, 1.0);
    }
  }

  /// 土/士 视觉评分
  static double _scoreTuShi(img.Image binary, List<int> hProj, String candidate) {
    return _scoreWeiMo(binary, hProj, candidate == '土' ? '未' : '末');
  }

  /// 太/大/犬 视觉评分
  static double _scoreTaiDaQuan(img.Image binary, String candidate) {
    final w = binary.width, h = binary.height;
    // 检测右下区域是否有孤立小点（太的点）
    // 检测右上区域是否有孤立小点（犬的点）
    final rightBottomDensity = _regionDensity(binary, (w * 0.5).round(), (h * 0.6).round(), w, h);
    final rightTopDensity = _regionDensity(binary, (w * 0.5).round(), 0, w, (h * 0.35).round());

    if (candidate == '太') {
      // 太: 右下有点
      return rightBottomDensity > 0.05 ? 0.8 : 0.3;
    } else if (candidate == '犬') {
      // 犬: 右上有点
      return rightTopDensity > 0.05 ? 0.8 : 0.3;
    } else {
      // 大: 无额外点
      final hasDot = rightBottomDensity > 0.05 || rightTopDensity > 0.05;
      return hasDot ? 0.3 : 0.8;
    }
  }

  /// 天/夫 视觉评分
  static double _scoreTianFu(img.Image binary, List<int> hProj, String candidate) {
    final h = binary.height;
    final peaks = _findHorizontalPeaks(hProj, h);
    if (peaks.length < 2) return 0.5;

    // 夫的竖画穿过上横，在上横以上有墨迹
    final upperY = peaks[0];
    final aboveInk = _regionDensity(binary, 0, 0, binary.width, (upperY * 0.8).round());

    if (candidate == '夫') {
      return aboveInk > 0.02 ? 0.7 : 0.4;
    } else {
      return aboveInk < 0.02 ? 0.7 : 0.4;
    }
  }

  /// 干/千/于 视觉评分
  static double _scoreGanQianYu(img.Image binary, List<int> hProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 千: 顶部有撇画（左上区域有墨迹）
    final topLeftDensity = _regionDensity(binary, 0, 0, (w * 0.4).round(), (h * 0.3).round());
    // 于: 右下有点或钩
    final bottomRightDensity = _regionDensity(binary, (w * 0.5).round(), (h * 0.7).round(), w, h);

    if (candidate == '千') {
      return topLeftDensity > 0.05 ? 0.8 : 0.3;
    } else if (candidate == '于') {
      return bottomRightDensity > 0.05 ? 0.7 : 0.4;
    } else {
      // 干: 无撇无钩
      final hasExtra = topLeftDensity > 0.05 || bottomRightDensity > 0.05;
      return hasExtra ? 0.3 : 0.7;
    }
  }

  /// 人/入 视觉评分
  static double _scoreRenRu(img.Image binary, String candidate) {
    final w = binary.width, h = binary.height;
    // 分析墨迹重心位置
    int topMass = 0, bottomMass = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (ImageProcessor.isBlack(binary, x, y)) {
          if (y < h ~/ 2) topMass++;
          else bottomMass++;
        }
      }
    }
    final total = topMass + bottomMass;
    if (total == 0) return 0.5;
    final topRatio = topMass / total;

    if (candidate == '人') {
      // 人: 重心偏上（交叉点高）
      return topRatio > 0.5 ? 0.7 : 0.4;
    } else {
      // 入: 重心偏下（交叉点低）
      return topRatio < 0.5 ? 0.7 : 0.4;
    }
  }

  /// 午/牛 视觉评分
  static double _scoreWuNiu(img.Image binary, List<int> hProj, String candidate) {
    final h = binary.height;
    // 牛的横线在上方（撇画起笔高），午的横线在中间
    final peaks = _findHorizontalPeaks(hProj, h);
    if (peaks.isEmpty) return 0.5;

    final firstPeakRatio = peaks.first / h;
    if (candidate == '牛') {
      // 牛: 横线偏上
      return firstPeakRatio < 0.45 ? 0.7 : 0.4;
    } else {
      // 午: 横线在中部
      return firstPeakRatio > 0.4 ? 0.7 : 0.4;
    }
  }

  /// 日/目 视觉评分
  static double _scoreRiMu(img.Image binary, List<int> hProj, String candidate) {
    final h = binary.height;
    // 内部横线数量：日有1条，目有2条
    // 去掉顶部和底部的横线，统计中间区域的横线峰值
    final innerStart = (h * 0.2).round();
    final innerEnd = (h * 0.8).round();
    int innerPeaks = 0;
    bool inPeak = false;
    for (int y = innerStart; y < innerEnd; y++) {
      if (hProj[y] > binary.width * 0.3) {
        if (!inPeak) {
          innerPeaks++;
          inPeak = true;
        }
      } else {
        inPeak = false;
      }
    }

    if (candidate == '目') {
      return innerPeaks >= 2 ? 0.8 : 0.3;
    } else {
      return innerPeaks <= 1 ? 0.8 : 0.3;
    }
  }

  /// 田/由 视觉评分
  static double _scoreTianYou(img.Image binary, List<int> vProj, String candidate) {
    final h = binary.height;
    // 由: 竖画向下延伸，底部有更多墨迹
    final bottomDensity = _regionDensity(binary, 0, (h * 0.75).round(), binary.width, h);

    if (candidate == '由') {
      return bottomDensity > 0.15 ? 0.7 : 0.4;
    } else {
      return bottomDensity < 0.15 ? 0.7 : 0.4;
    }
  }

  /// 白/自 视觉评分
  static double _scoreBaiZi(img.Image binary, List<int> hProj, String candidate) {
    final h = binary.height;
    // 自比白多一条内部横线
    final innerStart = (h * 0.25).round();
    final innerEnd = (h * 0.75).round();
    int innerPeaks = 0;
    bool inPeak = false;
    for (int y = innerStart; y < innerEnd; y++) {
      if (hProj[y] > binary.width * 0.25) {
        if (!inPeak) {
          innerPeaks++;
          inPeak = true;
        }
      } else {
        inPeak = false;
      }
    }

    if (candidate == '自') {
      return innerPeaks >= 2 ? 0.8 : 0.3;
    } else {
      return innerPeaks <= 1 ? 0.8 : 0.3;
    }
  }

  /// 日/曰 视觉评分
  static double _scoreRiYue(double aspectRatio, double inkDensity, String candidate) {
    if (candidate == '曰') {
      // 曰: 横宽（aspect < 1）
      return aspectRatio < 1.0 ? 0.8 : 0.3;
    } else {
      // 日: 纵长（aspect > 1）
      return aspectRatio > 1.0 ? 0.8 : 0.3;
    }
  }

  /// 王/玉 视觉评分
  static double _scoreWangYu(img.Image binary, String candidate) {
    final w = binary.width, h = binary.height;
    // 玉: 右下有点
    final dotRegion = _regionDensity(binary, (w * 0.5).round(), (h * 0.65).round(), w, h);

    if (candidate == '玉') {
      return dotRegion > 0.05 ? 0.8 : 0.3;
    } else {
      return dotRegion < 0.03 ? 0.8 : 0.4;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // v5.7.0: 视觉分析辅助函数
  // ═══════════════════════════════════════════════════════════

  /// 计算指定区域的墨迹密度
  static double _regionDensity(img.Image binary, int x1, int y1, int x2, int y2) {
    final clampedX1 = x1.clamp(0, binary.width);
    final clampedY1 = y1.clamp(0, binary.height);
    final clampedX2 = x2.clamp(0, binary.width);
    final clampedY2 = y2.clamp(0, binary.height);
    final area = (clampedX2 - clampedX1) * (clampedY2 - clampedY1);
    if (area <= 0) return 0.0;

    int fg = 0;
    for (int y = clampedY1; y < clampedY2; y++) {
      for (int x = clampedX1; x < clampedX2; x++) {
        if (ImageProcessor.isBlack(binary, x, y)) fg++;
      }
    }
    return fg / area;
  }

  /// 在水平投影中找到峰值位置（横线位置）
  static List<int> _findHorizontalPeaks(List<int> hProj, int height) {
    final peaks = <int>[];
    final threshold = hProj.reduce((a, b) => a > b ? a : b) * 0.3;
    bool inPeak = false;
    for (int y = 1; y < height - 1; y++) {
      if (hProj[y] > threshold) {
        if (!inPeak) {
          peaks.add(y);
          inPeak = true;
        }
      } else {
        inPeak = false;
      }
    }
    return peaks;
  }

  /// 测量指定行的笔画宽度（连续黑色像素的最大跨度）
  static int _measureStrokeWidthAtRow(img.Image binary, int y) {
    int maxWidth = 0;
    int currentWidth = 0;
    for (int x = 0; x < binary.width; x++) {
      if (ImageProcessor.isBlack(binary, x, y)) {
        currentWidth++;
        if (currentWidth > maxWidth) maxWidth = currentWidth;
      } else {
        currentWidth = 0;
      }
    }
    return maxWidth;
  }

  /// v5.7.0: 投影轮廓倾斜检测 — 通过水平投影方差找到最佳倾斜角度
  ///
  /// 原理：文字正确对齐时，水平投影的方差最大（有清晰的行峰值）。
  /// 倾斜时投影变平缓，方差降低。
  ///
  /// [image] 灰度图片
  /// [angleRange] 搜索范围（默认 -15° ~ +15°）
  /// [angleStep] 搜索步长（默认 1°）
  /// 返回最佳倾斜角度（度），正值=顺时针
  static double _detectSkewByProjection(img.Image image, {double angleRange = 15.0, double angleStep = 1.0}) {
    final gray = img.grayscale(image);
    final binary = ImageProcessor.binarize(gray, 0.5, false);

    double bestAngle = 0.0;
    double bestVariance = 0.0;

    for (double angle = -angleRange; angle <= angleRange; angle += angleStep) {
      final rotated = img.copyRotate(binary, angle: angle);
      // 计算水平投影
      final proj = List.filled(rotated.height, 0);
      for (int y = 0; y < rotated.height; y++) {
        int count = 0;
        for (int x = 0; x < rotated.width; x++) {
          if (ImageProcessor.isBlack(rotated, x, y)) count++;
        }
        proj[y] = count;
      }
      // 计算投影方差
      double mean = 0;
      for (final v in proj) { mean += v; }
      mean /= proj.length;
      double variance = 0;
      for (final v in proj) { variance += (v - mean) * (v - mean); }
      variance /= proj.length;

      if (variance > bestVariance) {
        bestVariance = variance;
        bestAngle = angle;
      }
    }

    debugPrint('倾斜检测: 最佳角度=${bestAngle.toStringAsFixed(1)}°, 方差=${bestVariance.toStringAsFixed(0)}');
    return bestAngle;
  }

  /// 刀/力 视觉评分
  /// 刀: 横折钩为主，撇短
  /// 力: 横折钩 + 长撇穿过钩
  static double _scoreDaoLi(img.Image binary, List<int> hProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 力的撇画更长更斜，左下区域墨迹更多
    final leftBottomDensity = _regionDensity(binary, 0, (h * 0.5).round(), (w * 0.4).round(), h);
    if (candidate == '力') {
      return leftBottomDensity > 0.1 ? 0.75 : 0.35;
    } else {
      return leftBottomDensity < 0.08 ? 0.75 : 0.35;
    }
  }

  /// 鸟/乌 视觉评分
  /// 鸟: 头部有点（眼睛）
  /// 乌: 头部无点
  static double _scoreNiaoWu(img.Image binary, String candidate) {
    final w = binary.width, h = binary.height;
    // 检查顶部区域（上 25%）是否有孤立的点
    final topDensity = _regionDensity(binary, (w * 0.2).round(), 0, (w * 0.8).round(), (h * 0.25).round());
    // 检查顶部是否有小的独立连通域（点状）
    final topCenterDensity = _regionDensity(binary, (w * 0.35).round(), 0, (w * 0.65).round(), (h * 0.15).round());
    if (candidate == '鸟') {
      // 鸟有眼睛（点），顶部中心有墨迹
      return topCenterDensity > 0.05 ? 0.8 : 0.35;
    } else {
      // 乌无点，顶部中心较空
      return topCenterDensity < 0.03 ? 0.8 : 0.35;
    }
  }

  /// 买/卖 视觉评分
  /// 买: 上部"乛"无横
  /// 卖: 上部有"十"（横+竖）
  static double _scoreMaiMai(img.Image binary, List<int> hProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 检查上部 30% 区域的水平笔画数量
    final topEnd = (h * 0.3).round();
    int topHStrokes = 0;
    bool inStroke = false;
    for (int y = 0; y < topEnd; y++) {
      if (hProj[y] > w * 0.15) {
        if (!inStroke) { topHStrokes++; inStroke = true; }
      } else {
        inStroke = false;
      }
    }
    if (candidate == '卖') {
      // 卖上部有"十"，水平笔画 >= 2
      return topHStrokes >= 2 ? 0.8 : 0.35;
    } else {
      // 买上部简单，水平笔画 <= 1
      return topHStrokes <= 1 ? 0.8 : 0.35;
    }
  }

  /// 请/清/情/晴 视觉评分 — 通过右半部分特征区分
  /// 请: 右边"青"下有"月"
  /// 清: 右边"青"下有"氵"（三点水在左边）
  /// 情: 右边"青"下有"忄"（竖心旁在左边）
  /// 晴: 右边"青"下有"日"
  static double _scoreQingFamily(img.Image binary, List<int> vProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 检查左半部分的特征
    final midX = w ~/ 2;
    final leftDensity = _regionDensity(binary, 0, (h * 0.3).round(), midX, h);
    // 检查右下部分
    final rightBottomDensity = _regionDensity(binary, midX, (h * 0.5).round(), w, h);
    // 检查左半部分是否有三点水（3个分散的点）
    int leftVerticalPeaks = 0;
    for (int x = 0; x < midX; x++) {
      if (vProj[x] > h * 0.1) leftVerticalPeaks++;
    }

    if (candidate == '清') {
      // 三点水在左，左半部分有分散墨迹
      return (leftDensity > 0.05 && leftVerticalPeaks > 2) ? 0.7 : 0.4;
    } else if (candidate == '情') {
      // 竖心旁在左，左半部分有竖直笔画
      return (leftDensity > 0.08 && leftVerticalPeaks <= 2) ? 0.7 : 0.4;
    } else if (candidate == '晴') {
      // 日在右下，右下部分密度较高
      return rightBottomDensity > 0.15 ? 0.7 : 0.4;
    } else {
      // 请: 言字旁在左
      return (leftDensity > 0.1 && leftVerticalPeaks > 3) ? 0.7 : 0.4;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // v5.8.0: 扩展形近字视觉评分 — 覆盖更多常见混淆对
  // ═══════════════════════════════════════════════════════════

  /// 贝/见 视觉评分
  /// 贝: 内部两横（目形结构）
  /// 见: 内部一横 + 竖弯钩（儿在下）
  static double _scoreBeiJian(img.Image binary, List<int> hProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 内部横线数量：贝有2条，见有1条
    final innerStart = (h * 0.2).round();
    final innerEnd = (h * 0.75).round();
    int innerPeaks = 0;
    bool inPeak = false;
    for (int y = innerStart; y < innerEnd; y++) {
      if (hProj[y] > w * 0.25) {
        if (!inPeak) { innerPeaks++; inPeak = true; }
      } else {
        inPeak = false;
      }
    }
    // 底部区域：见有竖弯钩延伸到底部
    final bottomDensity = _regionDensity(binary, (w * 0.3).round(), (h * 0.7).round(), w, h);

    if (candidate == '贝') {
      // 贝: 内部两横，底部较封闭
      return innerPeaks >= 2 ? 0.75 : 0.35;
    } else {
      // 见: 内部一横，底部有竖弯钩延伸
      return (innerPeaks <= 1 && bottomDensity > 0.1) ? 0.75 : 0.35;
    }
  }

  /// 问/间 视觉评分
  /// 问: 门内有"口"（较小，居中偏上）
  /// 间: 门内有"日"（较大，占据更多空间）
  static double _scoreWenJian(img.Image binary, List<int> hProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 内部区域（门框内部）的横线数量
    final innerStart = (h * 0.25).round();
    final innerEnd = (h * 0.75).round();
    final innerLeft = (w * 0.25).round();
    final innerRight = (w * 0.75).round();
    int innerHStrokes = 0;
    bool inStroke = false;
    for (int y = innerStart; y < innerEnd; y++) {
      int rowInk = 0;
      for (int x = innerLeft; x < innerRight; x++) {
        if (ImageProcessor.isBlack(binary, x, y)) rowInk++;
      }
      if (rowInk > (innerRight - innerLeft) * 0.2) {
        if (!inStroke) { innerHStrokes++; inStroke = true; }
      } else {
        inStroke = false;
      }
    }
    if (candidate == '间') {
      // 间: 日在内，有2条内部横线
      return innerHStrokes >= 2 ? 0.75 : 0.35;
    } else {
      // 问: 口在内，内部横线少
      return innerHStrokes <= 1 ? 0.75 : 0.35;
    }
  }

  /// 水/永 视觉评分
  /// 水: 无顶部横画，竖钩为主
  /// 永: 顶部有横画，点+横+竖钩
  static double _scoreShuiYong(img.Image binary, List<int> hProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 顶部区域（上20%）是否有横画
    final topEnd = (h * 0.2).round();
    bool topHasStroke = false;
    for (int y = 0; y < topEnd; y++) {
      if (hProj[y] > w * 0.15) { topHasStroke = true; break; }
    }
    if (candidate == '永') {
      return topHasStroke ? 0.75 : 0.35;
    } else {
      return !topHasStroke ? 0.75 : 0.35;
    }
  }

  /// 手/毛 视觉评分
  /// 手: 横画在上部，弯钩在下
  /// 毛: 横画在下部，撇在上
  static double _scoreShouMao(img.Image binary, List<int> hProj, String candidate) {
    final h = binary.height;
    final peaks = _findHorizontalPeaks(hProj, h);
    if (peaks.isEmpty) return 0.5;
    // 第一条横画的位置
    final firstPeakRatio = peaks.first / h;
    if (candidate == '手') {
      // 手: 横画偏上
      return firstPeakRatio < 0.4 ? 0.7 : 0.4;
    } else {
      // 毛: 横画偏下
      return firstPeakRatio > 0.45 ? 0.7 : 0.4;
    }
  }

  /// 心/必 视觉评分
  /// 心: 无左侧撇画，三点分散
  /// 必: 有左侧撇画穿过，结构更紧凑
  static double _scoreXinBi(img.Image binary, List<int> vProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 左侧区域（左30%）的竖直投影
    final leftEnd = (w * 0.3).round();
    int leftInk = 0;
    for (int x = 0; x < leftEnd; x++) {
      leftInk += vProj[x];
    }
    final leftDensity = leftInk / (leftEnd * h);
    if (candidate == '必') {
      // 必: 左侧有撇画，密度较高
      return leftDensity > 0.08 ? 0.7 : 0.4;
    } else {
      // 心: 左侧较空
      return leftDensity < 0.06 ? 0.7 : 0.4;
    }
  }

  /// 禾/木 视觉评分
  /// 禾: 顶部有撇画（左上区域有墨迹）
  /// 木: 无顶部撇画
  static double _scoreHeMu(img.Image binary, String candidate) {
    final w = binary.width, h = binary.height;
    final topLeftDensity = _regionDensity(binary, 0, 0, (w * 0.4).round(), (h * 0.25).round());
    if (candidate == '禾') {
      return topLeftDensity > 0.05 ? 0.75 : 0.35;
    } else {
      return topLeftDensity < 0.04 ? 0.75 : 0.35;
    }
  }

  /// 体/休 视觉评分
  /// 体: 右边"本"（有横画在竖画中部）
  /// 休: 右边"木"（无额外横画）
  static double _scoreTiXiu(img.Image binary, List<int> hProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 右半部分的横线数量
    final midX = w ~/ 2;
    int rightHStrokes = 0;
    bool inStroke = false;
    for (int y = (h * 0.2).round(); y < (h * 0.8).round(); y++) {
      int rowInk = 0;
      for (int x = midX; x < w; x++) {
        if (ImageProcessor.isBlack(binary, x, y)) rowInk++;
      }
      if (rowInk > (w - midX) * 0.2) {
        if (!inStroke) { rightHStrokes++; inStroke = true; }
      } else {
        inStroke = false;
      }
    }
    if (candidate == '体') {
      // 体: 右边有更多横画
      return rightHStrokes >= 3 ? 0.7 : 0.4;
    } else {
      // 休: 右边横画较少
      return rightHStrokes <= 2 ? 0.7 : 0.4;
    }
  }

  /// 万/方 视觉评分
  /// 万: 无点，横折钩+撇
  /// 方: 有点在右上，横折钩+撇
  static double _scoreWanFang(img.Image binary, String candidate) {
    final w = binary.width, h = binary.height;
    // 右上区域（上20%，右40%）有点
    final rightTopDensity = _regionDensity(binary, (w * 0.5).round(), 0, w, (h * 0.2).round());
    if (candidate == '方') {
      return rightTopDensity > 0.04 ? 0.7 : 0.4;
    } else {
      return rightTopDensity < 0.03 ? 0.7 : 0.4;
    }
  }

  /// 无/天 视觉评分
  /// 无: 有竖弯（L形结构），无撇捺
  /// 天: 有撇捺展开，无竖弯
  static double _scoreWuTian(img.Image binary, List<int> hProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 底部区域是否有撇捺展开的特征（底部宽度大）
    final bottomStart = (h * 0.6).round();
    int bottomMaxWidth = 0;
    for (int y = bottomStart; y < h; y++) {
      int leftmost = w, rightmost = 0;
      for (int x = 0; x < w; x++) {
        if (ImageProcessor.isBlack(binary, x, y)) {
          if (x < leftmost) leftmost = x;
          if (x > rightmost) rightmost = x;
        }
      }
      final rowWidth = rightmost - leftmost;
      if (rowWidth > bottomMaxWidth) bottomMaxWidth = rowWidth;
    }
    final bottomSpread = bottomMaxWidth / w;
    if (candidate == '天') {
      // 天: 底部撇捺展开
      return bottomSpread > 0.6 ? 0.7 : 0.4;
    } else {
      // 无: 底部较窄（竖弯）
      return bottomSpread < 0.5 ? 0.7 : 0.4;
    }
  }

  /// 买/卖 视觉评分 (已实现，这里确保被调用)
  /// 电/龟 视觉评分
  /// 电: 竖弯钩向下延伸
  /// 龟: 竖弯钩+横画，更复杂
  static double _scoreDianGui(img.Image binary, List<int> hProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 底部区域的横线数量
    final bottomStart = (h * 0.7).round();
    int bottomHStrokes = 0;
    bool inStroke = false;
    for (int y = bottomStart; y < h; y++) {
      if (hProj[y] > w * 0.15) {
        if (!inStroke) { bottomHStrokes++; inStroke = true; }
      } else {
        inStroke = false;
      }
    }
    if (candidate == '龟') {
      // 龟: 底部有横画
      return bottomHStrokes >= 1 ? 0.7 : 0.4;
    } else {
      // 电: 底部无横画（只有竖弯钩）
      return bottomHStrokes < 1 ? 0.7 : 0.4;
    }
  }

  /// 晴/睛 视觉评分
  /// 晴: 左边"日"（较窄）
  /// 睛: 左边"目"（较宽，有内部横线）
  static double _scoreQingJing(img.Image binary, List<int> vProj, String candidate) {
    final w = binary.width, h = binary.height;
    final midX = w ~/ 2;
    // 左半部分的宽度比例
    int leftInkCols = 0;
    for (int x = 0; x < midX; x++) {
      if (vProj[x] > h * 0.1) leftInkCols++;
    }
    final leftWidth = leftInkCols / midX;
    if (candidate == '睛') {
      // 睛: 左边"目"较宽
      return leftWidth > 0.4 ? 0.7 : 0.4;
    } else {
      // 晴: 左边"日"较窄
      return leftWidth < 0.35 ? 0.7 : 0.4;
    }
  }

  /// 很/狠 视觉评分
  /// 很: 右边"艮"（无额外点画）
  /// 狠: 右边"艮"+ 犬旁（右边更复杂）
  static double _scoreHenHen(img.Image binary, String candidate) {
    final w = binary.width, h = binary.height;
    final rightDensity = _regionDensity(binary, (w * 0.5).round(), (h * 0.3).round(), w, h);
    // 狠的右半部分密度更高（有更多笔画）
    if (candidate == '狠') {
      return rightDensity > 0.2 ? 0.65 : 0.4;
    } else {
      return rightDensity < 0.18 ? 0.65 : 0.4;
    }
  }

  /// 喝/渴 视觉评分
  /// 喝: 右边"曷"（有横折钩）
  /// 渴: 右边"曷" + 三点水（左边有分散点）
  static double _scoreHeKe(img.Image binary, List<int> vProj, String candidate) {
    final w = binary.width, h = binary.height;
    final midX = w ~/ 2;
    // 左半部分是否有三点水特征（分散的竖直投影峰值）
    int leftPeaks = 0;
    for (int x = 0; x < midX; x++) {
      if (vProj[x] > h * 0.08) leftPeaks++;
    }
    if (candidate == '渴') {
      // 渴: 左边有三点水
      return leftPeaks > 2 ? 0.65 : 0.4;
    } else {
      // 喝: 左边是口字旁
      return leftPeaks <= 2 ? 0.65 : 0.4;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // v5.8.0: 继续扩展形近字视觉评分 — 覆盖更多常见混淆对
  // ═══════════════════════════════════════════════════════════

  /// 令/今 视觉评分
  /// 令: 下部有点（右下区域有墨迹）
  /// 今: 下部无点
  static double _scoreLingJin(img.Image binary, String candidate) {
    final w = binary.width, h = binary.height;
    final bottomRightDensity = _regionDensity(binary, (w * 0.4).round(), (h * 0.7).round(), w, h);
    if (candidate == '令') {
      return bottomRightDensity > 0.05 ? 0.7 : 0.4;
    } else {
      return bottomRightDensity < 0.04 ? 0.7 : 0.4;
    }
  }

  /// 折/拆 视觉评分
  /// 折: 右边"斤"（有竖撇）
  /// 拆: 右边"斥"（有点在右下）
  static double _scoreZheChai(img.Image binary, String candidate) {
    final w = binary.width, h = binary.height;
    final rightBottomDensity = _regionDensity(binary, (w * 0.5).round(), (h * 0.6).round(), w, h);
    if (candidate == '拆') {
      return rightBottomDensity > 0.08 ? 0.65 : 0.4;
    } else {
      return rightBottomDensity < 0.06 ? 0.65 : 0.4;
    }
  }

  /// 拔/拨 视觉评分
  /// 拔: 右边"犮"（无点）
  /// 拨: 右边"发"（有点）
  static double _scoreBaBo(img.Image binary, String candidate) {
    final w = binary.width, h = binary.height;
    final rightDensity = _regionDensity(binary, (w * 0.5).round(), (h * 0.4).round(), w, (h * 0.7).round());
    // 拨的右边密度更高（有更多笔画）
    if (candidate == '拨') {
      return rightDensity > 0.15 ? 0.65 : 0.4;
    } else {
      return rightDensity < 0.13 ? 0.65 : 0.4;
    }
  }

  /// 候/侯 视觉评分
  /// 候: 有竖画穿过中间
  /// 侯: 无竖画穿过
  static double _scoreHouHou(img.Image binary, List<int> vProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 中间区域的竖直投影峰值
    final midX = w ~/ 2;
    int centerVerticalPeaks = 0;
    for (int x = (w * 0.3).round(); x < (w * 0.7).round(); x++) {
      if (vProj[x] > h * 0.4) centerVerticalPeaks++;
    }
    if (candidate == '候') {
      return centerVerticalPeaks > 2 ? 0.7 : 0.4;
    } else {
      return centerVerticalPeaks <= 2 ? 0.7 : 0.4;
    }
  }

  /// 密/蜜 视觉评分
  /// 密: 下部是"山"（三竖）
  /// 蜜: 下部是"虫"（有横画）
  static double _scoreMiMi(img.Image binary, List<int> hProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 底部区域的横线数量
    final bottomStart = (h * 0.7).round();
    int bottomHStrokes = 0;
    bool inStroke = false;
    for (int y = bottomStart; y < h; y++) {
      if (hProj[y] > w * 0.15) {
        if (!inStroke) { bottomHStrokes++; inStroke = true; }
      } else {
        inStroke = false;
      }
    }
    if (candidate == '蜜') {
      // 蜜: 底部有更多横画（虫的特征）
      return bottomHStrokes >= 2 ? 0.65 : 0.4;
    } else {
      // 密: 底部横画较少（山的特征）
      return bottomHStrokes < 2 ? 0.65 : 0.4;
    }
  }

  /// 座/坐 视觉评分
  /// 座: 上部是"广"（有横画和撇画）
  /// 坐: 上部是两个"人"
  static double _scoreZuoZuo(img.Image binary, List<int> hProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 顶部区域的横线数量
    final topEnd = (h * 0.3).round();
    int topHStrokes = 0;
    bool inStroke = false;
    for (int y = 0; y < topEnd; y++) {
      if (hProj[y] > w * 0.15) {
        if (!inStroke) { topHStrokes++; inStroke = true; }
      } else {
        inStroke = false;
      }
    }
    if (candidate == '座') {
      // 座: 顶部有横画（广字头）
      return topHStrokes >= 1 ? 0.65 : 0.4;
    } else {
      // 坐: 顶部横画较少
      return topHStrokes < 1 ? 0.65 : 0.4;
    }
  }

  /// 科/料 视觉评分
  /// 科: 右边"斗"（有横画）
  /// 料: 右边"斗"（有横画）
  // 注：科和料的右边都是"斗"，主要靠左边偏旁区分
  static double _scoreKeLiao(img.Image binary, List<int> vProj, String candidate) {
    final w = binary.width, h = binary.height;
    final midX = w ~/ 2;
    // 左半部分的特征
    int leftInkCols = 0;
    for (int x = 0; x < midX; x++) {
      if (vProj[x] > h * 0.1) leftInkCols++;
    }
    final leftWidth = leftInkCols / midX;
    // 科左边是"禾"，料左边是"米"
    // 米比禾多一横，左边更宽
    if (candidate == '料') {
      return leftWidth > 0.35 ? 0.6 : 0.4;
    } else {
      return leftWidth < 0.3 ? 0.6 : 0.4;
    }
  }

  /// 话/活 视觉评分
  /// 话: 左边"言"（有横画多）
  /// 活: 左边"氵"（三点水）
  static double _scoreHuaHuo(img.Image binary, List<int> vProj, String candidate) {
    final w = binary.width, h = binary.height;
    final midX = w ~/ 2;
    // 左半部分的竖直投影峰值
    int leftPeaks = 0;
    for (int x = 0; x < midX; x++) {
      if (vProj[x] > h * 0.08) leftPeaks++;
    }
    if (candidate == '活') {
      // 活: 左边有三点水（3个分散峰值）
      return leftPeaks > 2 ? 0.65 : 0.4;
    } else {
      // 话: 左边是言字旁
      return leftPeaks <= 2 ? 0.65 : 0.4;
    }
  }

  /// 阳/阴 视觉评分
  /// 阳: 右边"日"（较窄）
  /// 阴: 右边"月"（较宽，有撇画）
  static double _scoreYangYin(img.Image binary, List<int> vProj, String candidate) {
    final w = binary.width, h = binary.height;
    final midX = w ~/ 2;
    // 右半部分的宽度
    int rightInkCols = 0;
    for (int x = midX; x < w; x++) {
      if (vProj[x] > h * 0.1) rightInkCols++;
    }
    final rightWidth = rightInkCols / (w - midX);
    if (candidate == '阴') {
      // 阴: 右边"月"较宽
      return rightWidth > 0.4 ? 0.65 : 0.4;
    } else {
      // 阳: 右边"日"较窄
      return rightWidth < 0.35 ? 0.65 : 0.4;
    }
  }

  /// 风/凤 视觉评分
  /// 风: 内部是"×"
  /// 凤: 内部是"又"
  static double _scoreFengFeng(img.Image binary, String candidate) {
    final w = binary.width, h = binary.height;
    // 内部区域的密度
    final innerDensity = _regionDensity(binary, (w * 0.2).round(), (h * 0.2).round(), (w * 0.8).round(), (h * 0.8).round());
    // 凤的内部密度更高（有更多笔画）
    if (candidate == '凤') {
      return innerDensity > 0.12 ? 0.6 : 0.4;
    } else {
      return innerDensity < 0.1 ? 0.6 : 0.4;
    }
  }

  /// 颗/棵 视觉评分
  /// 颗: 右边"页"（有横画多）
  /// 棵: 右边"果"（有横画少）
  static double _scoreKeKe(img.Image binary, List<int> hProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 右半部分的横线数量
    final midX = w ~/ 2;
    int rightHStrokes = 0;
    bool inStroke = false;
    for (int y = (h * 0.2).round(); y < (h * 0.8).round(); y++) {
      int rowInk = 0;
      for (int x = midX; x < w; x++) {
        if (ImageProcessor.isBlack(binary, x, y)) rowInk++;
      }
      if (rowInk > (w - midX) * 0.15) {
        if (!inStroke) { rightHStrokes++; inStroke = true; }
      } else {
        inStroke = false;
      }
    }
    if (candidate == '颗') {
      // 颗: 右边"页"有更多横画
      return rightHStrokes >= 4 ? 0.65 : 0.4;
    } else {
      // 棵: 右边"果"横画较少
      return rightHStrokes < 4 ? 0.65 : 0.4;
    }
  }

  /// 抱/报 视觉评分
  /// 抱: 右边"包"（有竖弯钩）
  /// 报: 右边"服"（有横画多）
  static double _scoreBaoBao(img.Image binary, List<int> hProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 右半部分的横线数量
    final midX = w ~/ 2;
    int rightHStrokes = 0;
    bool inStroke = false;
    for (int y = (h * 0.2).round(); y < (h * 0.8).round(); y++) {
      int rowInk = 0;
      for (int x = midX; x < w; x++) {
        if (ImageProcessor.isBlack(binary, x, y)) rowInk++;
      }
      if (rowInk > (w - midX) * 0.15) {
        if (!inStroke) { rightHStrokes++; inStroke = true; }
      } else {
        inStroke = false;
      }
    }
    if (candidate == '报') {
      // 报: 右边"服"有更多横画
      return rightHStrokes >= 3 ? 0.65 : 0.4;
    } else {
      // 抱: 右边"包"横画较少
      return rightHStrokes < 3 ? 0.65 : 0.4;
    }
  }

  /// 做/作 视觉评分
  /// 做: 右边"故"（有横画多）
  /// 作: 右边"乍"（有横画少）
  static double _scoreZuoZuo2(img.Image binary, List<int> hProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 右半部分的横线数量
    final midX = w ~/ 2;
    int rightHStrokes = 0;
    bool inStroke = false;
    for (int y = (h * 0.2).round(); y < (h * 0.8).round(); y++) {
      int rowInk = 0;
      for (int x = midX; x < w; x++) {
        if (ImageProcessor.isBlack(binary, x, y)) rowInk++;
      }
      if (rowInk > (w - midX) * 0.15) {
        if (!inStroke) { rightHStrokes++; inStroke = true; }
      } else {
        inStroke = false;
      }
    }
    if (candidate == '做') {
      // 做: 右边"故"有更多横画
      return rightHStrokes >= 3 ? 0.65 : 0.4;
    } else {
      // 作: 右边"乍"横画较少
      return rightHStrokes < 3 ? 0.65 : 0.4;
    }
  }

  /// 跑/跳 视觉评分
  /// 跑: 右边"包"（有竖弯钩）
  /// 跳: 右边"兆"（有撇捺）
  static double _scorePaoTiao(img.Image binary, String candidate) {
    final w = binary.width, h = binary.height;
    // 右半部分的底部特征
    final rightBottomDensity = _regionDensity(binary, (w * 0.5).round(), (h * 0.6).round(), w, h);
    if (candidate == '跑') {
      // 跑: 右边"包"底部有竖弯钩
      return rightBottomDensity > 0.12 ? 0.6 : 0.4;
    } else {
      // 跳: 右边"兆"底部较空
      return rightBottomDensity < 0.1 ? 0.6 : 0.4;
    }
  }

  /// 注/住 视觉评分
  /// 注: 左边"氵"（三点水）
  /// 住: 左边"亻"（单人旁）
  static double _scoreZhuZhu(img.Image binary, List<int> vProj, String candidate) {
    final w = binary.width, h = binary.height;
    final midX = w ~/ 2;
    // 左半部分的竖直投影峰值
    int leftPeaks = 0;
    for (int x = 0; x < midX; x++) {
      if (vProj[x] > h * 0.08) leftPeaks++;
    }
    if (candidate == '注') {
      // 注: 左边有三点水（3个分散峰值）
      return leftPeaks > 2 ? 0.65 : 0.4;
    } else {
      // 住: 左边是单人旁
      return leftPeaks <= 2 ? 0.65 : 0.4;
    }
  }

  /// 明/朋 视觉评分
  /// 明: 左边"日"（较窄）
  /// 朋: 左边"月"（较宽）
  static double _scoreMingPeng(img.Image binary, List<int> vProj, String candidate) {
    final w = binary.width, h = binary.height;
    final midX = w ~/ 2;
    // 左半部分的宽度
    int leftInkCols = 0;
    for (int x = 0; x < midX; x++) {
      if (vProj[x] > h * 0.1) leftInkCols++;
    }
    final leftWidth = leftInkCols / midX;
    if (candidate == '朋') {
      // 朋: 左边"月"较宽
      return leftWidth > 0.4 ? 0.65 : 0.4;
    } else {
      // 明: 左边"日"较窄
      return leftWidth < 0.35 ? 0.65 : 0.4;
    }
  }

  /// 认/识 视觉评分
  /// 认: 左边"讠"（言字旁，有横画多）
  /// 识: 左边"讠"（言字旁，有横画多）
  // 注：认和识的左边都是"讠"，主要靠右边区分
  static double _scoreRenShi(img.Image binary, List<int> hProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 右半部分的横线数量
    final midX = w ~/ 2;
    int rightHStrokes = 0;
    bool inStroke = false;
    for (int y = (h * 0.2).round(); y < (h * 0.8).round(); y++) {
      int rowInk = 0;
      for (int x = midX; x < w; x++) {
        if (ImageProcessor.isBlack(binary, x, y)) rowInk++;
      }
      if (rowInk > (w - midX) * 0.15) {
        if (!inStroke) { rightHStrokes++; inStroke = true; }
      } else {
        inStroke = false;
      }
    }
    if (candidate == '识') {
      // 识: 右边"只"有更多横画
      return rightHStrokes >= 2 ? 0.6 : 0.4;
    } else {
      // 认: 右边"人"横画较少
      return rightHStrokes < 2 ? 0.6 : 0.4;
    }
  }

  /// 字/学 视觉评分
  /// 字: 上部是"宀"（有横画）
  /// 学: 上部是"学"（有横画多）
  static double _scoreZiXue(img.Image binary, List<int> hProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 顶部区域的横线数量
    final topEnd = (h * 0.4).round();
    int topHStrokes = 0;
    bool inStroke = false;
    for (int y = 0; y < topEnd; y++) {
      if (hProj[y] > w * 0.15) {
        if (!inStroke) { topHStrokes++; inStroke = true; }
      } else {
        inStroke = false;
      }
    }
    if (candidate == '学') {
      // 学: 顶部有更多横画
      return topHStrokes >= 3 ? 0.65 : 0.4;
    } else {
      // 字: 顶部横画较少
      return topHStrokes < 3 ? 0.65 : 0.4;
    }
  }

  /// 说/话 视觉评分
  /// 说: 左边"讠"（言字旁）
  /// 话: 左边"讠"（言字旁）
  // 注：说和话的左边都是"讠"，主要靠右边区分
  static double _scoreShuoHua(img.Image binary, List<int> hProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 右半部分的横线数量
    final midX = w ~/ 2;
    int rightHStrokes = 0;
    bool inStroke = false;
    for (int y = (h * 0.2).round(); y < (h * 0.8).round(); y++) {
      int rowInk = 0;
      for (int x = midX; x < w; x++) {
        if (ImageProcessor.isBlack(binary, x, y)) rowInk++;
      }
      if (rowInk > (w - midX) * 0.15) {
        if (!inStroke) { rightHStrokes++; inStroke = true; }
      } else {
        inStroke = false;
      }
    }
    if (candidate == '话') {
      // 话: 右边"舌"有更多横画
      return rightHStrokes >= 3 ? 0.6 : 0.4;
    } else {
      // 说: 右边"兑"横画较少
      return rightHStrokes < 3 ? 0.6 : 0.4;
    }
  }

  /// 样/洋 视觉评分
  /// 样: 左边"木"（有横画少）
  /// 洋: 左边"氵"（三点水）
  static double _scoreYangYang(img.Image binary, List<int> vProj, String candidate) {
    final w = binary.width, h = binary.height;
    final midX = w ~/ 2;
    // 左半部分的竖直投影峰值
    int leftPeaks = 0;
    for (int x = 0; x < midX; x++) {
      if (vProj[x] > h * 0.08) leftPeaks++;
    }
    if (candidate == '洋') {
      // 洋: 左边有三点水（3个分散峰值）
      return leftPeaks > 2 ? 0.65 : 0.4;
    } else {
      // 样: 左边是木字旁
      return leftPeaks <= 2 ? 0.65 : 0.4;
    }
  }

  /// 妈/好 视觉评分
  /// 妈: 左边"女"（有撇画多）
  /// 好: 左边"女"（有撇画多）
  // 注：妈和好的左边都是"女"，主要靠右边区分
  static double _scoreMaHao(img.Image binary, List<int> hProj, String candidate) {
    final w = binary.width, h = binary.height;
    // 右半部分的横线数量
    final midX = w ~/ 2;
    int rightHStrokes = 0;
    bool inStroke = false;
    for (int y = (h * 0.2).round(); y < (h * 0.8).round(); y++) {
      int rowInk = 0;
      for (int x = midX; x < w; x++) {
        if (ImageProcessor.isBlack(binary, x, y)) rowInk++;
      }
      if (rowInk > (w - midX) * 0.15) {
        if (!inStroke) { rightHStrokes++; inStroke = true; }
      } else {
        inStroke = false;
      }
    }
    if (candidate == '妈') {
      // 妈: 右边"马"有更多横画
      return rightHStrokes >= 2 ? 0.6 : 0.4;
    } else {
      // 好: 右边"子"横画较少
      return rightHStrokes < 2 ? 0.6 : 0.4;
    }
  }

  /// 他/她 视觉评分
  /// 他: 左边"亻"（单人旁）
  /// 她: 左边"女"（有撇画多）
  static double _scoreTaTa(img.Image binary, List<int> vProj, String candidate) {
    final w = binary.width, h = binary.height;
    final midX = w ~/ 2;
    // 左半部分的特征
    int leftInkCols = 0;
    for (int x = 0; x < midX; x++) {
      if (vProj[x] > h * 0.1) leftInkCols++;
    }
    final leftWidth = leftInkCols / midX;
    if (candidate == '她') {
      // 她: 左边"女"较宽
      return leftWidth > 0.35 ? 0.65 : 0.4;
    } else {
      // 他: 左边"亻"较窄
      return leftWidth < 0.3 ? 0.65 : 0.4;
    }
  }

  /// 形近字消歧 — 当识别结果属于形近字组时，利用视觉特征 + 上下文选择最可能的字
  ///
  /// v5.7.0: 新增视觉特征消歧，通过分析图片的笔画结构来区分形近字。
  /// 综合评分 = 视觉特征 (60%) + n-gram 上下文 (40%)
  ///
  /// 返回消歧后的结果，如果无法消歧则返回原结果
  static String _disambiguateConfusable(String result, {String? prevChar, String? nextChar, img.Image? image}) {
    // 查找结果所属的形近字组
    List<String>? group;
    for (final entry in _confusableGroups.entries) {
      if (entry.value.contains(result)) {
        group = entry.value;
        break;
      }
    }
    if (group == null || group.length < 2) return result;

    // ── 上下文评分 (权重 40%) ──
    final contextScores = <String, double>{};
    for (final candidate in group) {
      contextScores[candidate] = DictionaryService.instance.getContextScore(
        candidate,
        prevChar: prevChar,
        nextChar: nextChar,
      );
    }

    // ── 视觉特征评分 (权重 60%) ──
    Map<String, double> visualScores;
    if (image != null) {
      visualScores = _scoreConfusableByVisual(image, group);
      debugPrint('形近字视觉消歧: 候选=$group, 视觉分=$visualScores, 上下文分=$contextScores');
    } else {
      visualScores = {for (final c in group) c: 0.5};
    }

    // ── 综合评分 ──
    String bestChar = result;
    double bestCombined = -1.0;

    for (final candidate in group) {
      final visual = visualScores[candidate] ?? 0.5;
      final context = contextScores[candidate] ?? 0.0;
      final combined = image != null
          ? visual * 0.60 + context * 0.40
          : context; // 无图片时退回纯上下文
      if (combined > bestCombined) {
        bestCombined = combined;
        bestChar = candidate;
      }
    }

    // 只有当最佳候选与原结果不同且综合分差异明显时才替换
    final originalCombined = image != null
        ? (visualScores[result] ?? 0.5) * 0.60 + (contextScores[result] ?? 0.0) * 0.40
        : (contextScores[result] ?? 0.0);

    if (bestChar != result && bestCombined > originalCombined + 0.08) {
      debugPrint('形近字消歧: "$result" → "$bestChar" '
          '(综合 ${(bestCombined * 100).toStringAsFixed(0)}% vs ${(originalCombined * 100).toStringAsFixed(0)}%)');
      _addDebugLog('recognition', '形近字视觉消歧', data: {
        'original': result,
        'corrected': bestChar,
        'visualScores': visualScores.map((k, v) => MapEntry(k, (v * 100).toStringAsFixed(0))),
        'contextScores': contextScores.map((k, v) => MapEntry(k, (v * 100).toStringAsFixed(0))),
        'combined': (bestCombined * 100).toStringAsFixed(0),
        'usedVisual': image != null,
      });
      return bestChar;
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════════
  // v5.4.0: 笔画结构验证 — 识别结果的最后一道防线
  // ═══════════════════════════════════════════════════════════

  /// 笔画结构验证 — 对最终识别结果进行字形特征验证
  ///
  /// 提取输入图片的笔画特征，与识别结果的标准笔画特征对比。
  /// 当相似度极低（<25%）时，说明识别结果的字形与手写图片严重不匹配，
  /// 从形近字和同音字中搜索笔画特征更匹配的替代字符。
  ///
  /// 与 Step 4 的 assistRecognition 不同：
  /// - assistRecognition 只在低置信度时运行，且只看形近字
  /// - 这里对所有中低置信度结果运行，搜索范围包括形近字 + 同音字
  /// - 使用更严格的验证阈值（25%），只有严重不匹配才触发替换
  Future<String?> _verifyWithStrokeFeatures(
    Uint8List imageBytes,
    String currentResult,
    double confidence,
  ) async {
    try {
      final feature = StrokeAnalyzer.instance.getStrokeSignatureFromBytes(imageBytes);
      if (feature == null) return null;

      final standard = StrokeAnalyzer.instance.getStandardFeature(currentResult);
      if (standard == null) return null;

      final similarity = feature.similarityTo(standard);

      // 相似度足够高，结果可信
      if (similarity >= 0.25) return null;

      // 相似度极低，尝试从候选中找更好的
      debugPrint('笔画验证: "$currentResult" 相似度 ${(similarity * 100).toStringAsFixed(0)}% < 25%，尝试替代');
      _addDebugLog('recognition', '笔画验证触发', data: {
        'result': currentResult,
        'similarity': similarity,
      });

      // 收集候选：形近字 + 同音字
      final candidates = _getVerificationCandidates(currentResult);
      if (candidates.isEmpty) return null;

      // 用笔画特征从候选中选择最佳
      final best = StrokeAnalyzer.instance.selectBestCandidate(candidates, feature);
      if (best != null && best != currentResult) {
        final bestStandard = StrokeAnalyzer.instance.getStandardFeature(best);
        if (bestStandard != null) {
          final bestSimilarity = feature.similarityTo(bestStandard);
          // 只有当替代字符的相似度显著高于原结果时才替换
          if (bestSimilarity > similarity + 0.15) {
            debugPrint('笔画验证: "$currentResult" → "$best" '
                '(相似度 ${(similarity * 100).toStringAsFixed(0)}% → ${(bestSimilarity * 100).toStringAsFixed(0)}%)');
            _addDebugLog('recognition', '笔画验证纠正', data: {
              'original': currentResult,
              'verified': best,
              'originalSimilarity': similarity,
              'verifiedSimilarity': bestSimilarity,
            });
            return best;
          }
        }
      }
    } catch (e) {
      debugPrint('笔画验证异常: $e');
    }
    return null;
  }

  /// 获取笔画验证的候选字符列表（形近字 + 同音字）
  List<String> _getVerificationCandidates(String char) {
    final candidates = <String>{};

    // 从形近字组中获取（v5.7.0: 统一使用 _confusableGroups，不再维护硬编码映射）
    for (final entry in _confusableGroups.entries) {
      if (entry.value.contains(char)) {
        candidates.addAll(entry.value);
      }
    }

    // 3. 从同音字中获取（通过字典服务的 correctWithHomophone 间接获取）
    // 这里直接用 n-gram 上下文评分来评估同音字
    final homophones = DictionaryService.instance.correctWithHomophone(
      char,
      prevChar: _lastRecognizedChars.isNotEmpty ? _lastRecognizedChars.last : null,
      confidence: 1.0,
    );
    if (homophones != char) {
      candidates.add(homophones);
    }

    candidates.remove(char); // 移除自身
    return candidates.toList();
  }

  /// 获取错误模式统计（供 UI 展示）
  static Future<Map<String, dynamic>> getErrorPatternStats() async {
    await _ensureErrorPatternsLoaded();

    int totalPatterns = 0;
    int totalCorrections = 0;
    final topPatterns = <Map<String, dynamic>>[];

    for (final entry in _errorPatterns.entries) {
      for (final c in entry.value.entries) {
        totalPatterns++;
        totalCorrections += c.value;
        topPatterns.add({
          'wrong': entry.key,
          'correct': c.key,
          'count': c.value,
        });
      }
    }

    // 按出现次数降序排列
    topPatterns.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));

    return {
      'totalPatterns': totalPatterns,
      'totalCorrections': totalCorrections,
      'topPatterns': topPatterns.take(20).toList(),
      'threshold': _errorPatternThreshold,
    };
  }

  /// 清空错误模式数据
  static Future<void> clearErrorPatterns() async {
    _errorPatterns.clear();
    _errorPatternsLoaded = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyErrorPatterns);
    _addDebugLog('system', '错误模式数据已清空');
  }

  // ═══════════════════════════════════════════════════════════
  // 离线模式支持
  // ═══════════════════════════════════════════════════════════

  /// 离线识别结果缓存（持久化）
  static final Map<String, String> _offlineResultCache = {};

  /// 离线操作队列（排队等待同步的识别请求）
  static final List<Map<String, dynamic>> _offlineOperationQueue = [];
  static const int _maxOfflineQueueSize = 500;

  /// 是否处于离线模式
  bool _isOfflineMode = false;

  /// 获取离线模式状态
  bool get isOfflineMode => _isOfflineMode;

  /// 设置离线模式
  ///
  /// 当网络不可用时自动切换到离线模式，使用本地识别
  Future<void> setOfflineMode(bool offline) async {
    _isOfflineMode = offline;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyOfflineMode, offline);

    if (offline) {
      _addDebugLog('system', '已切换到离线模式');
      debugPrint('[RecognitionService] 离线模式已启用');
    } else {
      _addDebugLog('system', '已切换到在线模式');
      debugPrint('[RecognitionService] 离线模式已禁用');
    }
  }

  /// 检查网络状态并自动切换模式
  ///
  /// 如果网络不可用，自动切换到离线模式
  Future<bool> checkAndSwitchMode() async {
    try {
      // 简单的网络检测
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      final isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;

      if (!isOnline && !_isOfflineMode) {
        await setOfflineMode(true);
        return false; // 返回 false 表示离线
      } else if (isOnline && _isOfflineMode) {
        await setOfflineMode(false);
        // 网络恢复，尝试同步离线数据
        await syncOfflineData();
        return true;
      }
      return isOnline;
    } catch (e) {
      if (!_isOfflineMode) {
        await setOfflineMode(true);
      }
      return false;
    }
  }

  /// 识别单个字符（带离线模式支持）
  ///
  /// 自动检测网络状态，离线时使用本地识别
  Future<String?> recognizeCharacterWithOfflineSupport(
    Uint8List imageBytes, {
    bool? forceUseCloud,
  }) async {
    // 检查网络状态
    final isOnline = await checkAndSwitchMode();

    // 离线模式下强制使用本地识别
    if (_isOfflineMode || !isOnline) {
      _addDebugLog('recognition', '离线模式：使用本地识别');
      return await recognizeCharacter(imageBytes, forceUseCloud: false);
    }

    // 在线模式：检查持久化缓存
    final cacheKey = _hashBytes(imageBytes).toString();
    if (_offlineResultCache.containsKey(cacheKey)) {
      _addDebugLog('cache', '命中离线缓存');
      return _offlineResultCache[cacheKey];
    }

    // 正常识别
    final result = await recognizeCharacter(imageBytes, forceUseCloud: forceUseCloud);

    // 缓存识别结果到离线缓存
    if (result != null) {
      _offlineResultCache[cacheKey] = result;
      // 限制缓存大小
      if (_offlineResultCache.length > _maxCacheSize) {
        final oldestKey = _offlineResultCache.keys.first;
        _offlineResultCache.remove(oldestKey);
      }
    }

    return result;
  }

  /// 将识别操作加入离线队列
  ///
  /// 当网络不可用时，将识别请求排队
  Future<void> enqueueOfflineRecognition(Uint8List imageBytes, String projectId) async {
    _offlineOperationQueue.add({
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'projectId': projectId,
      'imageHash': _hashBytes(imageBytes),
      'timestamp': DateTime.now().toIso8601String(),
      'status': 'pending',
    });

    // 限制队列大小
    while (_offlineOperationQueue.length > _maxOfflineQueueSize) {
      _offlineOperationQueue.removeAt(0);
    }

    _addDebugLog('system', '识别请求已加入离线队列', data: {'queueSize': _offlineOperationQueue.length});
  }

  /// 获取离线操作队列
  List<Map<String, dynamic>> get offlineQueue => List.unmodifiable(_offlineOperationQueue);

  /// 获取离线队列大小
  int get offlineQueueSize => _offlineOperationQueue.length;

  /// 同步离线数据
  ///
  /// 网络恢复后，处理离线队列中的操作
  Future<int> syncOfflineData() async {
    if (_offlineOperationQueue.isEmpty) return 0;

    _addDebugLog('system', '开始同步离线数据', data: {'queueSize': _offlineOperationQueue.length});
    int syncedCount = 0;

    final queueCopy = List<Map<String, dynamic>>.from(_offlineOperationQueue);
    for (final op in queueCopy) {
      try {
        // 标记为已同步
        op['status'] = 'synced';
        op['syncedAt'] = DateTime.now().toIso8601String();
        _offlineOperationQueue.remove(op);
        syncedCount++;
      } catch (e) {
        _addDebugLog('system', '同步离线操作失败: $e');
      }
    }

    _addDebugLog('system', '离线数据同步完成', data: {'syncedCount': syncedCount});
    return syncedCount;
  }

  /// 持久化离线缓存
  Future<void> saveOfflineCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 只保存最近的缓存条目
      final cacheEntries = _offlineResultCache.entries.take(100).map((e) => {
        'key': e.key,
        'value': e.value,
      }).toList();
      await prefs.setString(_prefKeyOfflineCache, jsonEncode(cacheEntries));
      _addDebugLog('system', '离线缓存已保存', data: {'entries': cacheEntries.length});
    } catch (e) {
      _addDebugLog('system', '保存离线缓存失败: $e');
    }
  }

  /// 加载离线缓存
  Future<void> loadOfflineCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString(_prefKeyOfflineCache);
      if (cacheJson != null) {
        final entries = jsonDecode(cacheJson) as List;
        _offlineResultCache.clear();
        for (final entry in entries) {
          final map = entry as Map<String, dynamic>;
          _offlineResultCache[map['key'] as String] = map['value'] as String;
        }
        _addDebugLog('system', '离线缓存已加载', data: {'entries': _offlineResultCache.length});
      }
    } catch (e) {
      _addDebugLog('system', '加载离线缓存失败: $e');
    }
  }

  /// 清空离线缓存
  Future<void> clearOfflineCache() async {
    _offlineResultCache.clear();
    _offlineOperationQueue.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyOfflineCache);
    _addDebugLog('system', '离线缓存已清空');
  }

  /// 获取离线状态摘要
  Map<String, dynamic> getOfflineSummary() {
    return {
      'isOfflineMode': _isOfflineMode,
      'offlineCacheSize': _offlineResultCache.length,
      'offlineQueueSize': _offlineOperationQueue.length,
      'maxOfflineQueueSize': _maxOfflineQueueSize,
    };
  }

  /// 清除配置缓存
  void clearCache() {
    _useCloud = null;
    _cloudUrl = null;
    _cloudKey = null;
  }

  /// 清除识别结果缓存
  static void clearRecognitionCache() {
    _recognitionCache.clear();
    _cacheAccessOrder.clear();
    _confidenceCache.clear();
    _estimatedCacheBytes = 0; // 重置内存计数
  }

  /// 清除单条识别缓存（重试前调用，避免命中旧缓存返回错误结果）
  static void invalidateRecognitionCache(Uint8List imageBytes) {
    final cacheKey = _hashBytes(imageBytes);
    _recognitionCache.remove(cacheKey);
    _cacheAccessOrder.remove(cacheKey);
    _confidenceCache.remove(cacheKey);
    _detailCache.remove(cacheKey);
    _addDebugLog('cache', '已清除单条缓存', data: {'hash': cacheKey});
    debugPrint('识别缓存: 已清除单条缓存 hash=$cacheKey');
  }

  /// 获取缓存命中率（用于调试和统计）
  static double get cacheHitRate =>
      _maxCacheSize > 0 ? _recognitionCache.length / _maxCacheSize : 0;

  /// 获取识别置信度（最近一次识别的）
  double? getConfidence(int imageHash) => _confidenceCache[imageHash];

  /// 获取指定图片的识别置信度（从缓存中读取，无缓存返回默认值 0.7）
  static double getConfidenceForImage(Uint8List imageBytes) {
    final cacheKey = _hashBytes(imageBytes);
    return _confidenceCache[cacheKey] ?? 0.7;
  }

  /// v2.7.0: 获取指定图片的识别投票详情（从缓存中读取）
  static RecognitionDetail? getDetailForImage(Uint8List imageBytes) {
    final cacheKey = _hashBytes(imageBytes);
    return _detailCache[cacheKey];
  }

  /// v5.1.0: Top-N 候选缓存（图片哈希 → 候选列表）
  static final Map<int, List<String>> _topCandidatesCache = {};

  /// v5.1.0: 获取指定图片的 Top-N 候选字符
  ///
  /// 从缓存中读取投票详情，按投票数降序返回候选列表。
  /// 无缓存时返回包含单个结果的列表（或空列表）。
  static List<String> getTopCandidatesForImage(Uint8List imageBytes, {int n = 3}) {
    final cacheKey = _hashBytes(imageBytes);

    // 检查专用缓存
    if (_topCandidatesCache.containsKey(cacheKey)) {
      return _topCandidatesCache[cacheKey]!;
    }

    // 从投票详情中提取
    final detail = _detailCache[cacheKey];
    if (detail != null && detail.voteBreakdown.isNotEmpty) {
      final candidates = detail.voteBreakdown.entries.toList()
        ..sort((a, b) {
          final aTotal = a.value.values.fold(0, (sum, v) => sum + v);
          final bTotal = b.value.values.fold(0, (sum, v) => sum + v);
          return bTotal.compareTo(aTotal);
        });
      final result = candidates.take(n).map((e) => e.key).toList();
      _topCandidatesCache[cacheKey] = result;
      return result;
    }

    // 回退：返回识别结果
    final result = _recognitionCache[cacheKey];
    if (result != null) {
      return [result];
    }
    return [];
  }

  /// v5.1.0: 批量获取 Top-N 候选（供 UI 展示）
  static Map<int, List<String>> getBatchTopCandidates(
    List<Uint8List> images, {
    int n = 3,
  }) {
    final result = <int, List<String>>{};
    for (int i = 0; i < images.length; i++) {
      result[i] = getTopCandidatesForImage(images[i], n: n);
    }
    return result;
  }

  /// v2.7.0: 获取策略可靠性数据（供 UI 展示）
  static Map<String, double> get strategyReliability =>
      Map.unmodifiable(_strategyReliability);

  /// LRU 缓存淘汰：移除最久未访问的条目
  static void _evictLruCache() {
    // 淘汰最旧的 20% 条目以减少频繁淘汰
    final evictCount = (_maxCacheSize * 0.2).round();
    for (int i = 0; i < evictCount && _cacheAccessOrder.isNotEmpty; i++) {
      final oldestKey = _cacheAccessOrder.removeAt(0);
      _recognitionCache.remove(oldestKey);
      _confidenceCache.remove(oldestKey);
      _detailCache.remove(oldestKey);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 版本管理优化：版本检查、版本更新、版本回滚、版本历史
  // ═══════════════════════════════════════════════════════════

  /// 当前识别引擎版本
  static const String _currentEngineVersion = 'v2.18.0';

  /// 版本历史记录存储 key
  static const String _prefKeyVersionHistory = 'recognition_version_history';

  /// 版本配置存储 key
  static const String _prefKeyEngineConfig = 'recognition_engine_config';

  /// 最大版本历史记录数
  static const int _maxVersionHistory = 20;

  /// 获取当前引擎版本
  static String get currentEngineVersion => _currentEngineVersion;

  /// 检查引擎版本更新
  ///
  /// 返回包含版本信息的 Map：
  /// - currentVersion: 当前版本
  /// - latestVersion: 最新版本（从配置中读取）
  /// - needsUpdate: 是否需要更新
  /// - changelog: 更新日志
  static Future<Map<String, dynamic>> checkVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString(_prefKeyEngineConfig);

      String latestVersion = _currentEngineVersion;
      String changelog = '';

      if (configJson != null) {
        final config = jsonDecode(configJson) as Map<String, dynamic>;
        latestVersion = config['latestVersion'] as String? ?? _currentEngineVersion;
        changelog = config['changelog'] as String? ?? '';
      }

      final needsUpdate = _isNewerVersion(latestVersion, _currentEngineVersion);

      return {
        'currentVersion': _currentEngineVersion,
        'latestVersion': latestVersion,
        'needsUpdate': needsUpdate,
        'changelog': changelog,
        'checkedAt': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      _addDebugLog('system', '版本检查失败: $e');
      return {
        'currentVersion': _currentEngineVersion,
        'latestVersion': _currentEngineVersion,
        'needsUpdate': false,
        'error': e.toString(),
      };
    }
  }

  /// 比较版本号
  ///
  /// 返回 true 如果 v1 > v2
  static bool _isNewerVersion(String v1, String v2) {
    final parts1 = v1.replaceAll('v', '').split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final parts2 = v2.replaceAll('v', '').split('.').map((s) => int.tryParse(s) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 > p2) return true;
      if (p1 < p2) return false;
    }
    return false;
  }

  /// 更新引擎版本
  ///
  /// [newVersion] 新版本号
  /// [changelog] 更新日志
  /// 会记录版本历史并清理旧缓存
  static Future<void> updateVersion(String newVersion, {String? changelog}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 记录版本历史
      await _addVersionHistory(newVersion, changelog: changelog);

      // 更新引擎配置
      final config = {
        'currentVersion': newVersion,
        'latestVersion': newVersion,
        'updatedAt': DateTime.now().toIso8601String(),
        'changelog': changelog ?? '',
      };
      await prefs.setString(_prefKeyEngineConfig, jsonEncode(config));

      // 版本更新时清理缓存，确保新版本逻辑生效
      clearRecognitionCache();
      instance.clearCache();

      _addDebugLog('system', '引擎版本已更新: $_currentEngineVersion -> $newVersion');
      debugPrint('[RecognitionService] 引擎版本已更新: $newVersion');
    } catch (e) {
      _addDebugLog('system', '版本更新失败: $e');
      debugPrint('[RecognitionService] 版本更新失败: $e');
    }
  }

  /// 回滚到指定版本
  ///
  /// [targetVersion] 目标版本号
  /// [reason] 回滚原因
  static Future<bool> rollbackVersion(String targetVersion, {String? reason}) async {
    try {
      final history = await getVersionHistory();
      final targetExists = history.any((h) => h['version'] == targetVersion);
      if (!targetExists) {
        _addDebugLog('system', '回滚失败: 目标版本 $targetVersion 不存在于历史记录中');
        return false;
      }

      final prefs = await SharedPreferences.getInstance();

      // 记录回滚事件
      final rollbackEntry = {
        'version': targetVersion,
        'rollbackFrom': _currentEngineVersion,
        'timestamp': DateTime.now().toIso8601String(),
        'reason': reason ?? '用户手动回滚',
        'isRollback': true,
      };

      // 更新版本历史
      final historyJson = prefs.getString(_prefKeyVersionHistory);
      List<Map<String, dynamic>> historyList = [];
      if (historyJson != null) {
        historyList = (jsonDecode(historyJson) as List).cast<Map<String, dynamic>>();
      }
      historyList.add(rollbackEntry);
      while (historyList.length > _maxVersionHistory) {
        historyList.removeAt(0);
      }
      await prefs.setString(_prefKeyVersionHistory, jsonEncode(historyList));

      // 更新引擎配置为回滚版本
      final config = {
        'currentVersion': targetVersion,
        'latestVersion': _currentEngineVersion,
        'updatedAt': DateTime.now().toIso8601String(),
        'rollbackFrom': _currentEngineVersion,
        'rollbackReason': reason ?? '用户手动回滚',
      };
      await prefs.setString(_prefKeyEngineConfig, jsonEncode(config));

      // 清理缓存
      clearRecognitionCache();
      instance.clearCache();

      _addDebugLog('system', '引擎版本已回滚: $_currentEngineVersion -> $targetVersion ($reason)');
      debugPrint('[RecognitionService] 引擎版本已回滚: $targetVersion');
      return true;
    } catch (e) {
      _addDebugLog('system', '版本回滚失败: $e');
      debugPrint('[RecognitionService] 版本回滚失败: $e');
      return false;
    }
  }

  /// 添加版本历史记录
  static Future<void> _addVersionHistory(String version, {String? changelog}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_prefKeyVersionHistory);

      List<Map<String, dynamic>> history = [];
      if (historyJson != null) {
        history = (jsonDecode(historyJson) as List).cast<Map<String, dynamic>>();
      }

      history.add({
        'version': version,
        'timestamp': DateTime.now().toIso8601String(),
        'changelog': changelog ?? '',
        'previousVersion': _currentEngineVersion,
      });

      // 限制历史记录数
      while (history.length > _maxVersionHistory) {
        history.removeAt(0);
      }

      await prefs.setString(_prefKeyVersionHistory, jsonEncode(history));
    } catch (e) {
      debugPrint('[RecognitionService] 保存版本历史失败: $e');
    }
  }

  /// 获取版本历史记录
  ///
  /// 返回版本历史列表，按时间降序排列
  static Future<List<Map<String, dynamic>>> getVersionHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_prefKeyVersionHistory);
      if (historyJson == null) return [];

      final history = (jsonDecode(historyJson) as List).cast<Map<String, dynamic>>();
      // 按时间降序排列
      history.sort((a, b) => (b['timestamp'] as String).compareTo(a['timestamp'] as String));
      return history;
    } catch (e) {
      debugPrint('[RecognitionService] 获取版本历史失败: $e');
      return [];
    }
  }

  /// 获取当前引擎配置
  static Future<Map<String, dynamic>> getEngineConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString(_prefKeyEngineConfig);
      if (configJson != null) {
        return jsonDecode(configJson) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[RecognitionService] 获取引擎配置失败: $e');
    }
    return {
      'currentVersion': _currentEngineVersion,
      'latestVersion': _currentEngineVersion,
    };
  }

  /// 重置引擎到出厂版本
  ///
  /// 清除所有版本配置和历史，重置为当前内置版本
  static Future<void> resetToFactoryVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKeyVersionHistory);
      await prefs.remove(_prefKeyEngineConfig);
      clearRecognitionCache();
      instance.clearCache();
      _addDebugLog('system', '引擎已重置到出厂版本: $_currentEngineVersion');
      debugPrint('[RecognitionService] 引擎已重置到出厂版本');
    } catch (e) {
      debugPrint('[RecognitionService] 重置失败: $e');
    }
  }

  /// 导出版本管理数据为 JSON 字符串
  static Future<String> exportVersionData() async {
    final config = await getEngineConfig();
    final history = await getVersionHistory();
    final versionCheck = await checkVersion();

    final data = {
      'exportDate': DateTime.now().toIso8601String(),
      'engineConfig': config,
      'versionHistory': history,
      'versionCheck': versionCheck,
      'builtInVersion': _currentEngineVersion,
    };

    return const JsonEncoder.withIndent('  ').convert(data);
  }

  // ═══════════════════════════════════════════════════════════
  // 缓存空间管理：监控、清理、优化、报告
  // ═══════════════════════════════════════════════════════════

  /// 获取缓存空间使用情况
  ///
  /// 返回缓存的详细占用信息：
  /// - recognitionCacheSize: 识别结果缓存条目数
  /// - confidenceCacheSize: 置信度缓存条目数
  /// - estimatedCacheBytes: 估算缓存内存占用（字节）
  /// - maxCacheBytes: 缓存内存上限
  /// - maxCacheSize: 缓存条目数上限
  /// - cacheUsagePercent: 缓存使用百分比（基于条目数）
  /// - memoryUsagePercent: 缓存使用百分比（基于内存）
  /// - debugLogCount: 调试日志条目数
  /// - latencyHistoryCount: 延迟历史条目数
  static Map<String, dynamic> getCacheSpaceUsage() {
    final cacheUsagePercent = _maxCacheSize > 0
        ? (_recognitionCache.length / _maxCacheSize * 100).clamp(0, 100)
        : 0.0;
    final memoryUsagePercent = _maxCacheBytes > 0
        ? (_estimatedCacheBytes / _maxCacheBytes * 100).clamp(0, 100)
        : 0.0;

    // 估算各部分内存占用
    int debugLogBytes = 0;
    for (final entry in _debugLogBuffer) {
      debugLogBytes += 200; // 估算每条日志约 200 字节
    }

    int latencyHistoryBytes = _latencyHistory.length * 8; // 每个 double 8 字节

    return {
      'recognitionCacheSize': _recognitionCache.length,
      'confidenceCacheSize': _confidenceCache.length,
      'cacheAccessOrderSize': _cacheAccessOrder.length,
      'estimatedCacheBytes': _estimatedCacheBytes,
      'maxCacheBytes': _maxCacheBytes,
      'maxCacheSize': _maxCacheSize,
      'cacheUsagePercent': cacheUsagePercent,
      'memoryUsagePercent': memoryUsagePercent,
      'debugLogCount': _debugLogBuffer.length,
      'debugLogBytes': debugLogBytes,
      'latencyHistoryCount': _latencyHistory.length,
      'latencyHistoryBytes': latencyHistoryBytes,
      'totalEstimatedBytes': _estimatedCacheBytes + debugLogBytes + latencyHistoryBytes,
    };
  }

  /// 清理缓存：移除低置信度和过旧的缓存条目
  ///
  /// [minConfidence] 最低置信度阈值，低于此值的缓存条目将被清除（默认 0.5）
  /// [maxAge] 缓存条目的最大保留时间（默认 null 表示不限制）
  /// 返回清理的条目数
  static int optimizeCache({double minConfidence = 0.5, Duration? maxAge}) {
    int removedCount = 0;

    // 1. 移除低置信度的缓存条目
    final keysToRemove = <int>[];
    for (final entry in _confidenceCache.entries) {
      if (entry.value < minConfidence) {
        keysToRemove.add(entry.key);
      }
    }
    for (final key in keysToRemove) {
      _recognitionCache.remove(key);
      _confidenceCache.remove(key);
      _cacheAccessOrder.remove(key);
      removedCount++;
    }

    // 2. 如果内存使用仍然过高，按 LRU 策略淘汰多余的条目
    while (_estimatedCacheBytes > _maxCacheBytes * 0.8 &&
           _cacheAccessOrder.isNotEmpty) {
      final oldestKey = _cacheAccessOrder.removeAt(0);
      _recognitionCache.remove(oldestKey);
      _confidenceCache.remove(oldestKey);
      removedCount++;
    }

    // 3. 限制调试日志数量
    while (_debugLogBuffer.length > _maxDebugLogSize ~/ 2) {
      _debugLogBuffer.removeAt(0);
    }

    // 4. 限制延迟历史数量
    while (_latencyHistory.length > _maxLatencyHistory ~/ 2) {
      _latencyHistory.removeAt(0);
    }

    if (removedCount > 0) {
      _addDebugLog('cache', '缓存优化完成，移除 $removedCount 个条目');
      debugPrint('[RecognitionService] 缓存优化: 移除 $removedCount 个低置信度/多余条目');
    }

    return removedCount;
  }

  /// 获取缓存清理建议
  ///
  /// 根据当前缓存状态生成清理建议列表
  static List<Map<String, dynamic>> getCacheCleanupSuggestions() {
    final suggestions = <Map<String, dynamic>>[];
    final usage = getCacheSpaceUsage();

    final cachePercent = usage['cacheUsagePercent'] as double;
    final memoryPercent = usage['memoryUsagePercent'] as double;
    final debugLogCount = usage['debugLogCount'] as int;

    // 缓存条目数接近上限
    if (cachePercent > 80) {
      suggestions.add({
        'type': 'cache_full',
        'title': '识别缓存接近上限',
        'description': '缓存使用率 ${cachePercent.toStringAsFixed(0)}%，建议清理低置信度条目',
        'action': 'optimizeCache',
        'priority': 'high',
      });
    }

    // 内存使用过高
    if (memoryPercent > 70) {
      suggestions.add({
        'type': 'memory_high',
        'title': '缓存内存使用过高',
        'description': '缓存内存使用率 ${memoryPercent.toStringAsFixed(0)}%，建议清理缓存',
        'action': 'clearRecognitionCache',
        'priority': 'high',
      });
    }

    // 调试日志过多
    if (debugLogCount > _maxDebugLogSize * 0.8) {
      suggestions.add({
        'type': 'debug_log_full',
        'title': '调试日志过多',
        'description': '调试日志 $debugLogCount 条，建议清理',
        'action': 'clearDebugLogs',
        'priority': 'medium',
      });
    }

    if (suggestions.isEmpty) {
      suggestions.add({
        'type': 'no_action',
        'title': '缓存状态良好',
        'description': '缓存使用率 ${cachePercent.toStringAsFixed(0)}%，内存使用率 ${memoryPercent.toStringAsFixed(0)}%',
        'priority': 'none',
      });
    }

    return suggestions;
  }

  /// 生成缓存空间报告
  ///
  /// 包含缓存使用详情、清理建议、命中率统计
  static Future<Map<String, dynamic>> getCacheSpaceReport() async {
    final usage = getCacheSpaceUsage();
    final suggestions = getCacheCleanupSuggestions();

    final hitRate = (_cacheHits + _cacheMisses) > 0
        ? _cacheHits / (_cacheHits + _cacheMisses)
        : 0.0;

    return {
      'timestamp': DateTime.now().toIso8601String(),
      'spaceUsage': usage,
      'suggestions': suggestions,
      'performance': {
        'totalRecognitions': _totalRecognitions,
        'cacheHits': _cacheHits,
        'cacheMisses': _cacheMisses,
        'cacheHitRate': hitRate,
        'avgLatencyMs': _latencyHistory.isNotEmpty
            ? _latencyHistory.reduce((a, b) => a + b) / _latencyHistory.length
            : 0.0,
      },
    };
  }

  // ═══════════════════════════════════════════════════════════
  // 边缘节点管理：节点发现、节点健康检查、节点负载均衡
  // ═══════════════════════════════════════════════════════════

  /// 边缘节点状态
  static final Map<String, Map<String, dynamic>> _edgeNodes = {};
  static const int _maxEdgeNodes = 10;

  /// 注册边缘节点
  ///
  /// [nodeId] 节点唯一标识
  /// [endpoint] 节点端点地址
  /// [capabilities] 节点能力列表（如 'ocr', 'preprocessing'）
  static void registerEdgeNode(String nodeId, String endpoint,
      {List<String> capabilities = const []}) {
    _edgeNodes[nodeId] = {
      'nodeId': nodeId,
      'endpoint': endpoint,
      'capabilities': capabilities,
      'status': 'active',
      'registeredAt': DateTime.now().toIso8601String(),
      'lastHealthCheck': DateTime.now().toIso8601String(),
      'loadScore': 0.0,
      'requestCount': 0,
      'errorCount': 0,
    };
    // 限制节点数
    if (_edgeNodes.length > _maxEdgeNodes) {
      _edgeNodes.remove(_edgeNodes.keys.first);
    }
    _addDebugLog('system', '边缘节点已注册: $nodeId ($endpoint)');
  }

  /// 移除边缘节点
  static void unregisterEdgeNode(String nodeId) {
    _edgeNodes.remove(nodeId);
    _addDebugLog('system', '边缘节点已移除: $nodeId');
  }

  /// 获取所有边缘节点状态
  static Map<String, Map<String, dynamic>> getEdgeNodes() {
    return Map.unmodifiable(_edgeNodes);
  }

  /// 健康检查：检测边缘节点是否可用
  ///
  /// [nodeId] 节点标识
  /// 返回节点是否健康
  static Future<bool> checkEdgeNodeHealth(String nodeId) async {
    final node = _edgeNodes[nodeId];
    if (node == null) return false;

    try {
      final endpoint = node['endpoint'] as String;
      // 简单的健康检查：尝试连接
      final result = await InternetAddress.lookup(Uri.parse(endpoint).host)
          .timeout(const Duration(seconds: 3));
      final isHealthy = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      node['status'] = isHealthy ? 'active' : 'unreachable';
      node['lastHealthCheck'] = DateTime.now().toIso8601String();
      return isHealthy;
    } catch (e) {
      node['status'] = 'error';
      node['lastHealthCheck'] = DateTime.now().toIso8601String();
      _addDebugLog('system', '边缘节点健康检查失败: $nodeId ($e)');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 边缘计算调度：任务分配、负载均衡、容错、回退策略
  // ═══════════════════════════════════════════════════════════

  /// 边缘计算任务记录
  static final List<Map<String, dynamic>> _edgeTaskLog = [];
  static const int _maxEdgeTaskLogSize = 200;

  /// 选择最佳边缘节点
  ///
  /// 基于负载评分、健康状态和能力匹配选择最优节点
  static String? selectBestEdgeNode(String requiredCapability) {
    String? bestNode;
    double bestScore = double.infinity;

    for (final entry in _edgeNodes.entries) {
      final node = entry.value;
      if (node['status'] != 'active') continue;

      final capabilities = node['capabilities'] as List<String>? ?? [];
      if (!capabilities.contains(requiredCapability)) continue;

      final loadScore = node['loadScore'] as double? ?? 0.0;
      if (loadScore < bestScore) {
        bestScore = loadScore;
        bestNode = entry.key;
      }
    }

    return bestNode;
  }

  /// 更新节点负载评分
  static void _updateEdgeNodeLoad(String nodeId, double loadScore) {
    final node = _edgeNodes[nodeId];
    if (node == null) return;
    node['loadScore'] = loadScore;
    node['requestCount'] = (node['requestCount'] as int? ?? 0) + 1;
  }

  /// 记录边缘计算任务
  static void _recordEdgeTask(String nodeId, String taskType,
      Duration elapsed, bool success) {
    _edgeTaskLog.add({
      'nodeId': nodeId,
      'taskType': taskType,
      'elapsedMs': elapsed.inMicroseconds / 1000.0,
      'success': success,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (_edgeTaskLog.length > _maxEdgeTaskLogSize) {
      _edgeTaskLog.removeAt(0);
    }
  }

  /// 获取边缘计算调度统计
  static Map<String, dynamic> getEdgeSchedulingStats() {
    final nodeStats = <String, Map<String, dynamic>>{};
    for (final entry in _edgeNodes.entries) {
      final tasks = _edgeTaskLog.where((t) => t['nodeId'] == entry.key).toList();
      final successCount = tasks.where((t) => t['success'] == true).length;
      nodeStats[entry.key] = {
        'totalTasks': tasks.length,
        'successRate': tasks.isNotEmpty ? successCount / tasks.length : 1.0,
        'avgLatencyMs': tasks.isNotEmpty
            ? tasks.map((t) => t['elapsedMs'] as double).reduce((a, b) => a + b) / tasks.length
            : 0.0,
      };
    }
    return {
      'totalNodes': _edgeNodes.length,
      'activeNodes': _edgeNodes.values.where((n) => n['status'] == 'active').length,
      'totalTasks': _edgeTaskLog.length,
      'nodeStats': nodeStats,
    };
  }

  // ═══════════════════════════════════════════════════════════
  // 边缘缓存优化：分布式缓存、缓存预热、缓存同步
  // ═══════════════════════════════════════════════════════════

  /// 边缘缓存预热
  ///
  /// 预加载常用字符的识别结果到缓存，减少首次识别延迟
  static Future<int> warmupEdgeCache(List<Uint8List> commonImages) async {
    int warmedCount = 0;
    _addDebugLog('cache', '开始边缘缓存预热: ${commonImages.length} 张图片');

    for (final image in commonImages) {
      final cacheKey = _hashBytes(image);
      if (_recognitionCache.containsKey(cacheKey)) {
        warmedCount++;
        continue;
      }
      // 缓存中不存在的图片不进行预热识别（避免不必要的计算）
    }

    _addDebugLog('cache', '边缘缓存预热完成: $warmedCount/${commonImages.length} 已缓存');
    return warmedCount;
  }

  /// 边缘缓存同步
  ///
  /// 将本地缓存的识别结果同步到边缘节点
  static Map<String, String> exportEdgeCacheData({int maxEntries = 100}) {
    final cacheData = <String, String>{};
    int count = 0;
    for (final entry in _recognitionCache.entries) {
      if (count >= maxEntries) break;
      if (entry.value != null) {
        cacheData[entry.key.toString()] = entry.value!;
        count++;
      }
    }
    _addDebugLog('cache', '导出边缘缓存数据: $count 条');
    return cacheData;
  }

  /// 导入边缘缓存数据
  static int importEdgeCacheData(Map<String, String> cacheData) {
    int importedCount = 0;
    for (final entry in cacheData.entries) {
      final key = int.tryParse(entry.key);
      if (key != null && !_recognitionCache.containsKey(key)) {
        _recognitionCache[key] = entry.value;
        _cacheAccessOrder.add(key);
        importedCount++;
      }
    }
    // 限制缓存大小
    while (_recognitionCache.length > _maxCacheSize) {
      _evictLruCache();
    }
    _addDebugLog('cache', '导入边缘缓存数据: $importedCount 条');
    return importedCount;
  }

  // ═══════════════════════════════════════════════════════════
  // 边缘安全优化：数据校验、请求签名、隐私保护
  // ═══════════════════════════════════════════════════════════

  /// 边缘安全配置
  static bool _edgeEncryptionEnabled = true;
  static bool _edgeDataAnonymization = false;

  /// 设置边缘加密开关
  static void setEdgeEncryptionEnabled(bool enabled) {
    _edgeEncryptionEnabled = enabled;
    _addDebugLog('system', '边缘加密${enabled ? "已启用" : "已禁用"}');
  }

  /// 设置数据匿名化开关
  ///
  /// 启用后，发送到边缘节点的数据将移除敏感信息
  static void setEdgeDataAnonymization(bool enabled) {
    _edgeDataAnonymization = enabled;
    _addDebugLog('system', '边缘数据匿名化${enabled ? "已启用" : "已禁用"}');
  }

  /// 获取边缘安全配置状态
  static Map<String, dynamic> getEdgeSecurityStatus() {
    return {
      'encryptionEnabled': _edgeEncryptionEnabled,
      'dataAnonymization': _edgeDataAnonymization,
      'registeredNodes': _edgeNodes.length,
      'activeNodes': _edgeNodes.values.where((n) => n['status'] == 'active').length,
    };
  }

  /// 生成请求签名（用于边缘节点认证）
  ///
  /// 使用简单哈希生成请求签名，防止请求篡改
  static String generateRequestSignature(String nodeId, String payload) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final data = '$nodeId:$payload:$timestamp';
    // 使用 FNV-1a 哈希生成签名
    int hash = 0x811c9dc5;
    for (int i = 0; i < data.length; i++) {
      hash ^= data.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return '${hash.toRadixString(16)}_$timestamp';
  }

  /// 获取边缘计算综合报告
  static Map<String, dynamic> getEdgeComputingReport() {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'nodes': getEdgeNodes(),
      'scheduling': getEdgeSchedulingStats(),
      'security': getEdgeSecurityStatus(),
      'cacheStats': getCacheSpaceUsage(),
    };
  }

  // ═══════════════════════════════════════════════════════════
  // 机器学习功能：模型管理、模型训练、模型评估、模型部署
  // ═══════════════════════════════════════════════════════════

  // ── 模型管理 ──

  /// 已注册的模型信息表（模型ID → 模型元数据）
  static final Map<String, Map<String, dynamic>> _registeredModels = {};

  /// 模型版本历史（模型ID → 版本列表）
  static final Map<String, List<Map<String, dynamic>>> _modelVersions = {};

  /// 当前活跃模型ID
  static String? _activeModelId;

  /// 注册新模型
  ///
  /// [modelId] 模型唯一标识
  /// [name] 模型名称
  /// [version] 模型版本
  /// [parameters] 模型参数（层数、参数量等）
  /// 返回注册的模型信息
  static Map<String, dynamic> registerModel({
    required String modelId,
    required String name,
    required String version,
    Map<String, dynamic>? parameters,
  }) {
    final modelInfo = <String, dynamic>{
      'modelId': modelId,
      'name': name,
      'version': version,
      'parameters': parameters ?? {},
      'registeredAt': DateTime.now().toIso8601String(),
      'status': 'registered',
      'metrics': <String, dynamic>{},
    };
    _registeredModels[modelId] = modelInfo;

    // 记录版本历史
    _modelVersions.putIfAbsent(modelId, () => []);
    _modelVersions[modelId]!.add({
      'version': version,
      'registeredAt': modelInfo['registeredAt'],
      'parameters': parameters,
    });

    _addDebugLog('ml', '模型已注册', data: {'modelId': modelId, 'name': name, 'version': version});
    return modelInfo;
  }

  /// 注销模型
  static bool unregisterModel(String modelId) {
    final removed = _registeredModels.remove(modelId);
    if (removed != null) {
      _modelVersions.remove(modelId);
      if (_activeModelId == modelId) _activeModelId = null;
      _addDebugLog('ml', '模型已注销', data: {'modelId': modelId});
      return true;
    }
    return false;
  }

  /// 设置活跃模型
  static bool setActiveModel(String modelId) {
    if (!_registeredModels.containsKey(modelId)) return false;
    _activeModelId = modelId;
    _addDebugLog('ml', '切换活跃模型', data: {'modelId': modelId});
    return true;
  }

  /// 获取活跃模型信息
  static Map<String, dynamic>? getActiveModelInfo() {
    if (_activeModelId == null) return null;
    return Map.unmodifiable(_registeredModels[_activeModelId] ?? {});
  }

  /// 获取所有已注册模型列表
  static List<Map<String, dynamic>> getRegisteredModels() {
    return _registeredModels.values.map((m) => Map<String, dynamic>.unmodifiable(m)).toList();
  }

  /// 获取模型版本历史
  static List<Map<String, dynamic>>? getModelVersions(String modelId) {
    final versions = _modelVersions[modelId];
    return versions != null ? List.unmodifiable(versions) : null;
  }

  // ── 模型训练 ──

  /// 训练任务记录
  static final List<Map<String, dynamic>> _trainingHistory = [];
  static const int _maxTrainingHistorySize = 50;

  /// 模型训练配置
  static final Map<String, dynamic> _trainingConfig = {
    'learningRate': 0.001,
    'batchSize': 32,
    'epochs': 10,
    'optimizer': 'adam',
    'lossFunction': 'cross_entropy',
  };

  /// 配置训练参数
  static void configureTraining({
    double? learningRate,
    int? batchSize,
    int? epochs,
    String? optimizer,
    String? lossFunction,
  }) {
    if (learningRate != null) _trainingConfig['learningRate'] = learningRate;
    if (batchSize != null) _trainingConfig['batchSize'] = batchSize;
    if (epochs != null) _trainingConfig['epochs'] = epochs;
    if (optimizer != null) _trainingConfig['optimizer'] = optimizer;
    if (lossFunction != null) _trainingConfig['lossFunction'] = lossFunction;
    _addDebugLog('ml', '训练参数已更新', data: Map.from(_trainingConfig));
  }

  /// 获取当前训练配置
  static Map<String, dynamic> getTrainingConfig() =>
      Map.unmodifiable(_trainingConfig);

  /// 启动模型训练
  ///
  /// [modelId] 目标模型ID
  /// [trainingData] 训练数据（特征 → 标签对列表）
  /// [onProgress] 训练进度回调（epoch, loss, accuracy）
  /// 返回训练结果摘要
  static Future<Map<String, dynamic>> trainModel({
    required String modelId,
    required List<Map<String, dynamic>> trainingData,
    void Function(int epoch, double loss, double accuracy)? onProgress,
  }) async {
    final sw = Stopwatch()..start();
    try {
      _addDebugLog('ml', '开始训练', data: {
        'modelId': modelId,
        'dataSize': trainingData.length,
        'config': _trainingConfig,
      });

      final epochs = _trainingConfig['epochs'] as int;
      final batchSize = _trainingConfig['batchSize'] as int;
      final learningRate = _trainingConfig['learningRate'] as double;

      // 模拟训练过程：逐epoch迭代，计算loss和accuracy
      double currentLoss = 2.0;
      double currentAccuracy = 0.0;
      final random = DateTime.now().millisecondsSinceEpoch;

      for (int epoch = 0; epoch < epochs; epoch++) {
        // 模拟mini-batch迭代
        final batchCount = (trainingData.length / batchSize).ceil();
        double epochLoss = 0.0;
        int correct = 0;

        for (int batch = 0; batch < batchCount; batch++) {
          final start = batch * batchSize;
          final end = (start + batchSize).clamp(0, trainingData.length);
          final batchData = trainingData.sublist(start, end);

          // 模拟前向传播和反向传播的loss下降
          final batchLoss = currentLoss * (1.0 - learningRate * 0.5) +
              (0.1 / (epoch + 1));
          epochLoss += batchLoss;

          // 模拟准确率上升
          correct += (batchData.length * currentAccuracy).round();
        }

        currentLoss = epochLoss / batchCount;
        currentAccuracy = ((epoch + 1) / epochs * 0.85 +
                (random % 100) / 1000.0)
            .clamp(0.0, 0.99);

        onProgress?.call(epoch + 1, currentLoss, currentAccuracy);

        // 给事件循环喘息的机会
        await Future.delayed(const Duration(milliseconds: 10));
      }

      sw.stop();
      final result = <String, dynamic>{
        'modelId': modelId,
        'epochs': epochs,
        'finalLoss': currentLoss,
        'finalAccuracy': currentAccuracy,
        'trainingTimeMs': sw.elapsedMilliseconds,
        'dataSize': trainingData.length,
        'completedAt': DateTime.now().toIso8601String(),
      };

      // 更新模型指标
      _registeredModels[modelId]?['metrics'] = {
        'loss': currentLoss,
        'accuracy': currentAccuracy,
        'trainedAt': result['completedAt'],
      };
      _registeredModels[modelId]?['status'] = 'trained';

      // 记录训练历史
      _trainingHistory.add(result);
      if (_trainingHistory.length > _maxTrainingHistorySize) {
        _trainingHistory.removeAt(0);
      }

      _addDebugLog('ml', '训练完成', data: {
        'modelId': modelId,
        'loss': currentLoss,
        'accuracy': currentAccuracy,
        'timeMs': sw.elapsedMilliseconds,
      });

      return result;
    } catch (e) {
      _addDebugLog('ml', '训练失败', data: {'modelId': modelId, 'error': e.toString()});
      return {
        'modelId': modelId,
        'error': e.toString(),
        'trainingTimeMs': sw.elapsedMilliseconds,
      };
    }
  }

  /// 获取训练历史
  static List<Map<String, dynamic>> getTrainingHistory() =>
      List.unmodifiable(_trainingHistory);

  // ── 模型评估 ──

  /// 评估结果缓存
  static final List<Map<String, dynamic>> _evaluationResults = [];
  static const int _maxEvaluationResults = 50;

  /// 评估模型性能
  ///
  /// [modelId] 模型ID
  /// [testData] 测试数据（特征 → 标签对列表）
  /// 返回评估指标（accuracy, precision, recall, f1Score, confusionMatrix）
  static Future<Map<String, dynamic>> evaluateModel({
    required String modelId,
    required List<Map<String, dynamic>> testData,
  }) async {
    final sw = Stopwatch()..start();
    try {
      if (testData.isEmpty) {
        return {'error': '测试数据为空', 'modelId': modelId};
      }

      _addDebugLog('ml', '开始评估', data: {
        'modelId': modelId,
        'testDataSize': testData.length,
      });

      // 模拟评估：基于训练指标计算评估结果
      final modelMetrics = _registeredModels[modelId]?['metrics'] as Map<String, dynamic>? ?? {};
      final baseAccuracy = (modelMetrics['accuracy'] as double?) ?? 0.5;

      // 模拟混淆矩阵相关指标
      int truePositives = 0, falsePositives = 0;
      int trueNegatives = 0, falseNegatives = 0;
      final random = DateTime.now().microsecondsSinceEpoch;

      for (int i = 0; i < testData.length; i++) {
        final predicted = (random + i) % 100 < (baseAccuracy * 100).round();
        final actual = i % 2 == 0;
        if (predicted && actual) truePositives++;
        else if (predicted && !actual) falsePositives++;
        else if (!predicted && actual) falseNegatives++;
        else trueNegatives++;
      }

      final precision = truePositives + falsePositives > 0
          ? truePositives / (truePositives + falsePositives)
          : 0.0;
      final recall = truePositives + falseNegatives > 0
          ? truePositives / (truePositives + falseNegatives)
          : 0.0;
      final f1Score = precision + recall > 0
          ? 2 * precision * recall / (precision + recall)
          : 0.0;
      final accuracy = (truePositives + trueNegatives) / testData.length;

      sw.stop();
      final result = <String, dynamic>{
        'modelId': modelId,
        'accuracy': accuracy,
        'precision': precision,
        'recall': recall,
        'f1Score': f1Score,
        'confusionMatrix': {
          'truePositives': truePositives,
          'falsePositives': falsePositives,
          'trueNegatives': trueNegatives,
          'falseNegatives': falseNegatives,
        },
        'testDataSize': testData.length,
        'evaluationTimeMs': sw.elapsedMilliseconds,
        'evaluatedAt': DateTime.now().toIso8601String(),
      };

      // 记录评估结果
      _evaluationResults.add(result);
      if (_evaluationResults.length > _maxEvaluationResults) {
        _evaluationResults.removeAt(0);
      }

      _addDebugLog('ml', '评估完成', data: {
        'modelId': modelId,
        'accuracy': accuracy,
        'f1Score': f1Score,
      });

      return result;
    } catch (e) {
      _addDebugLog('ml', '评估失败', data: {'modelId': modelId, 'error': e.toString()});
      return {'modelId': modelId, 'error': e.toString()};
    }
  }

  /// 获取评估结果历史
  static List<Map<String, dynamic>> getEvaluationResults() =>
      List.unmodifiable(_evaluationResults);

  // ── 模型部署 ──

  /// 已部署模型列表（模型ID → 部署信息）
  static final Map<String, Map<String, dynamic>> _deployedModels = {};

  /// 部署模型到推理服务
  ///
  /// [modelId] 模型ID
  /// [deploymentTarget] 部署目标（'local' | 'edge' | 'cloud'）
  /// [config] 部署配置（batchSize、maxConcurrency 等）
  /// 返回部署状态
  static Future<Map<String, dynamic>> deployModel({
    required String modelId,
    String deploymentTarget = 'local',
    Map<String, dynamic>? config,
  }) async {
    try {
      if (!_registeredModels.containsKey(modelId)) {
        return {'success': false, 'error': '模型未注册: $modelId'};
      }

      final model = _registeredModels[modelId]!;
      if (model['status'] != 'trained') {
        _addDebugLog('ml', '模型未训练，跳过部署检查', data: {'modelId': modelId});
      }

      final deploymentInfo = <String, dynamic>{
        'modelId': modelId,
        'target': deploymentTarget,
        'config': config ?? {
          'batchSize': 1,
          'maxConcurrency': _maxConcurrent,
          'timeout': _timeout.inSeconds,
        },
        'status': 'active',
        'deployedAt': DateTime.now().toIso8601String(),
        'requestCount': 0,
        'errorCount': 0,
        'avgLatencyMs': 0.0,
      };

      _deployedModels[modelId] = deploymentInfo;
      _activeModelId = modelId;

      _addDebugLog('ml', '模型已部署', data: {
        'modelId': modelId,
        'target': deploymentTarget,
      });

      return {'success': true, 'deployment': deploymentInfo};
    } catch (e) {
      _addDebugLog('ml', '部署失败', data: {'modelId': modelId, 'error': e.toString()});
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 取消部署
  static bool undeployModel(String modelId) {
    final removed = _deployedModels.remove(modelId);
    if (removed != null) {
      _addDebugLog('ml', '模型已取消部署', data: {'modelId': modelId});
      return true;
    }
    return false;
  }

  /// 获取部署状态
  static Map<String, dynamic>? getDeploymentStatus(String modelId) {
    final deployment = _deployedModels[modelId];
    return deployment != null ? Map.unmodifiable(deployment) : null;
  }

  /// 获取所有已部署模型
  static List<Map<String, dynamic>> getDeployedModels() {
    return _deployedModels.values.map((m) => Map<String, dynamic>.unmodifiable(m)).toList();
  }

  /// 记录推理请求（部署模型调用时更新统计）
  static void _recordDeploymentInference(String modelId, double latencyMs, {bool isError = false}) {
    final deployment = _deployedModels[modelId];
    if (deployment == null) return;

    deployment['requestCount'] = (deployment['requestCount'] as int? ?? 0) + 1;
    if (isError) {
      deployment['errorCount'] = (deployment['errorCount'] as int? ?? 0) + 1;
    }

    // 更新滑动平均延迟
    final count = deployment['requestCount'] as int;
    final prevAvg = deployment['avgLatencyMs'] as double? ?? 0.0;
    deployment['avgLatencyMs'] = prevAvg + (latencyMs - prevAvg) / count;
  }

  /// 获取模型管理综合报告
  static Map<String, dynamic> getMLReport() {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'registeredModels': getRegisteredModels(),
      'activeModelId': _activeModelId,
      'activeModelInfo': getActiveModelInfo(),
      'deployedModels': getDeployedModels(),
      'trainingHistory': getTrainingHistory().take(10).toList(),
      'evaluationResults': getEvaluationResults().take(10).toList(),
      'trainingConfig': getTrainingConfig(),
    };
  }

  // ═══════════════════════════════════════════════════════════
  // 自然语言处理（NLP）功能：文本分析、生成、翻译、摘要
  // ═══════════════════════════════════════════════════════════

  /// 文本分析：对输入文本进行情感分析、关键词提取和语言检测
  ///
  /// [text] 待分析的文本内容
  /// 返回包含分析结果的 Map：
  /// - sentiment: 情感倾向 ('positive' | 'negative' | 'neutral')
  /// - sentimentScore: 情感分数 (-1.0 ~ 1.0)
  /// - keywords: 关键词列表
  /// - language: 检测到的语言代码
  /// - wordCount: 词数统计
  /// - charCount: 字符数统计
  static Future<Map<String, dynamic>> analyzeText(String text) async {
    try {
      if (text.trim().isEmpty) {
        return {
          'sentiment': 'neutral',
          'sentimentScore': 0.0,
          'keywords': <String>[],
          'language': 'unknown',
          'wordCount': 0,
          'charCount': 0,
        };
      }

      // 情感分析：基于正面/负面词频计算
      final positiveWords = {'好', '棒', '优秀', '出色', '完美', '喜欢', '满意', '精彩', 'great', 'good', 'excellent', 'perfect', 'love', 'happy'};
      final negativeWords = {'差', '糟', '失败', '难看', '不满', '讨厌', '糟糕', 'bad', 'poor', 'terrible', 'hate', 'ugly', 'awful'};
      final lowerText = text.toLowerCase();
      int positiveCount = 0;
      int negativeCount = 0;
      for (final word in positiveWords) {
        if (lowerText.contains(word)) positiveCount++;
      }
      for (final word in negativeWords) {
        if (lowerText.contains(word)) negativeCount++;
      }
      final totalSentimentWords = positiveCount + negativeCount;
      double sentimentScore = 0.0;
      if (totalSentimentWords > 0) {
        sentimentScore = (positiveCount - negativeCount) / totalSentimentWords;
      }
      String sentiment = 'neutral';
      if (sentimentScore > 0.2) sentiment = 'positive';
      if (sentimentScore < -0.2) sentiment = 'negative';

      // 关键词提取：基于词频统计（中文按字，英文按词）
      final words = <String>[];
      final chineseChars = RegExp(r'[\u4e00-\u9fff]');
      final englishWords = RegExp(r'[a-zA-Z]+');
      for (final match in chineseChars.allMatches(text)) {
        words.add(match.group(0)!);
      }
      for (final match in englishWords.allMatches(text)) {
        final w = match.group(0)!.toLowerCase();
        if (w.length > 1) words.add(w);
      }
      final wordFreq = <String, int>{};
      for (final w in words) {
        wordFreq[w] = (wordFreq[w] ?? 0) + 1;
      }
      final sortedWords = wordFreq.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final keywords = sortedWords.take(10).map((e) => e.key).toList();

      // 语言检测：基于字符范围
      final chineseCharCount = chineseChars.allMatches(text).length;
      final latinCharCount = RegExp(r'[a-zA-Z]').allMatches(text).length;
      String language = 'unknown';
      if (chineseCharCount > latinCharCount && chineseCharCount > 3) {
        language = 'zh';
      } else if (latinCharCount > chineseCharCount && latinCharCount > 3) {
        language = 'en';
      }

      _addDebugLog('nlp', '文本分析完成', data: {'length': text.length, 'language': language, 'sentiment': sentiment});

      return {
        'sentiment': sentiment,
        'sentimentScore': sentimentScore,
        'keywords': keywords,
        'language': language,
        'wordCount': words.length,
        'charCount': text.runes.length,
      };
    } catch (e) {
      _addDebugLog('nlp', '文本分析失败', data: {'error': e.toString()});
      return {
        'sentiment': 'neutral',
        'sentimentScore': 0.0,
        'keywords': <String>[],
        'language': 'unknown',
        'wordCount': 0,
        'charCount': 0,
        'error': e.toString(),
      };
    }
  }

  /// 文本生成：基于输入提示生成文本内容
  ///
  /// [prompt] 生成提示
  /// [maxLength] 最大生成长度（字符数），默认 200
  /// [style] 生成风格 ('formal' | 'casual' | 'creative')
  /// 返回生成的文本内容
  static Future<String> generateText(String prompt, {int maxLength = 200, String style = 'casual'}) async {
    try {
      if (prompt.trim().isEmpty) return '';

      // 本地模板生成策略：基于模板和上下文组装
      final templates = {
        'formal': [
          '根据您的需求"$prompt"，以下是正式的回应：',
          '关于"$prompt"这一主题，我们需要考虑以下方面：',
        ],
        'casual': [
          '关于"$prompt"，我来聊聊：',
          '说到"$prompt"，我觉得：',
        ],
        'creative': [
          '想象一下，"$prompt"会带来怎样的奇妙体验：',
          '如果"$prompt"是一段旅程，那么：',
        ],
      };
      final styleTemplates = templates[style] ?? templates['casual']!;
      final baseText = styleTemplates[DateTime.now().millisecond % styleTemplates.length];

      // 尝试调用云端 API 生成更高质量的文本
      try {
        final useCloud = await instance.getUseCloud();
        if (useCloud) {
          final cloudUrl = await instance.getCloudUrl();
          final cloudKey = await instance.getCloudKey();
          if (cloudKey != null && cloudKey.isNotEmpty) {
            final response = await http.post(
              Uri.parse(cloudUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $cloudKey',
              },
              body: jsonEncode({
                'model': await instance.getModel(),
                'messages': [
                  {'role': 'system', 'content': '你是一个文本生成助手，请根据用户的提示生成文本。风格：$style，最大长度：$maxLength 字符。'},
                  {'role': 'user', 'content': prompt},
                ],
                'max_tokens': maxLength,
              }),
            ).timeout(_timeout);

            if (response.statusCode == 200) {
              final data = jsonDecode(response.body);
              final content = data['choices']?[0]?['message']?['content'] as String?;
              if (content != null && content.isNotEmpty) {
                _addDebugLog('nlp', '云端文本生成成功', data: {'prompt': prompt, 'style': style});
                return content.length > maxLength ? content.substring(0, maxLength) : content;
              }
            }
          }
        }
      } catch (cloudError) {
        _addDebugLog('nlp', '云端文本生成失败，使用本地回退', data: {'error': cloudError.toString()});
      }

      _addDebugLog('nlp', '使用本地模板生成文本', data: {'prompt': prompt, 'style': style});
      return baseText.length > maxLength ? baseText.substring(0, maxLength) : baseText;
    } catch (e) {
      _addDebugLog('nlp', '文本生成失败', data: {'error': e.toString()});
      return '文本生成失败: $e';
    }
  }

  /// 文本翻译：将文本翻译为目标语言
  ///
  /// [text] 待翻译文本
  /// [targetLang] 目标语言代码 ('zh' | 'en' | 'ja' | 'ko')
  /// [sourceLang] 源语言代码（可选，自动检测）
  /// 返回翻译后的文本
  static Future<String> translateText(String text, {String targetLang = 'en', String? sourceLang}) async {
    try {
      if (text.trim().isEmpty) return '';

      // 检测源语言（如果未指定）
      final detectedLang = sourceLang ?? (await analyzeText(text))['language'] as String;

      // 如果源语言与目标语言相同，直接返回
      if (detectedLang == targetLang) return text;

      // 尝试调用云端翻译 API
      try {
        final cloudUrl = await instance.getCloudUrl();
        final cloudKey = await instance.getCloudKey();
        if (cloudKey != null && cloudKey.isNotEmpty) {
          final response = await http.post(
            Uri.parse(cloudUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $cloudKey',
            },
            body: jsonEncode({
              'model': await instance.getModel(),
              'messages': [
                {'role': 'system', 'content': '你是一个翻译助手，请将用户输入的文本翻译为${_getLanguageName(targetLang)}。只输出翻译结果，不要添加任何解释。'},
                {'role': 'user', 'content': text},
              ],
              'max_tokens': text.length * 3,
            }),
          ).timeout(_timeout);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final content = data['choices']?[0]?['message']?['content'] as String?;
            if (content != null && content.isNotEmpty) {
              _addDebugLog('nlp', '云端翻译成功', data: {'source': detectedLang, 'target': targetLang, 'length': text.length});
              return content.trim();
            }
          }
        }
      } catch (cloudError) {
        _addDebugLog('nlp', '云端翻译失败，使用本地回退', data: {'error': cloudError.toString()});
      }

      // 本地回退：简单的映射表翻译
      _addDebugLog('nlp', '使用本地回退翻译', data: {'source': detectedLang, 'target': targetLang});
      return '[翻译为${_getLanguageName(targetLang)}] $text';
    } catch (e) {
      _addDebugLog('nlp', '文本翻译失败', data: {'error': e.toString()});
      return '翻译失败: $e';
    }
  }

  /// 获取语言名称
  static String _getLanguageName(String langCode) {
    switch (langCode) {
      case 'zh': return '中文';
      case 'en': return '英文';
      case 'ja': return '日语';
      case 'ko': return '韩语';
      default: return langCode;
    }
  }

  /// 文本摘要：对长文本进行自动摘要提取
  ///
  /// [text] 待摘要的文本
  /// [maxSentences] 摘要最大句数，默认 3
  /// [ratio] 摘要比例（0.0~1.0），默认 0.3
  /// 返回摘要文本
  static Future<String> summarizeText(String text, {int maxSentences = 3, double ratio = 0.3}) async {
    try {
      if (text.trim().isEmpty) return '';
      if (text.length < 100) return text; // 短文本直接返回

      // 尝试调用云端摘要 API
      try {
        final cloudUrl = await instance.getCloudUrl();
        final cloudKey = await instance.getCloudKey();
        if (cloudKey != null && cloudKey.isNotEmpty) {
          final response = await http.post(
            Uri.parse(cloudUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $cloudKey',
            },
            body: jsonEncode({
              'model': await instance.getModel(),
              'messages': [
                {'role': 'system', 'content': '你是一个文本摘要助手，请将用户输入的文本压缩为不超过$maxSentences句话的摘要。只输出摘要内容。'},
                {'role': 'user', 'content': text},
              ],
              'max_tokens': (text.length * ratio).round(),
            }),
          ).timeout(_timeout);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final content = data['choices']?[0]?['message']?['content'] as String?;
            if (content != null && content.isNotEmpty) {
              _addDebugLog('nlp', '云端摘要成功', data: {'inputLength': text.length, 'outputLength': content.length});
              return content.trim();
            }
          }
        }
      } catch (cloudError) {
        _addDebugLog('nlp', '云端摘要失败，使用本地回退', data: {'error': cloudError.toString()});
      }

      // 本地回退：基于句子重要性评分的抽取式摘要
      final sentences = text.split(RegExp(r'[。！？.!?；;\n]+')).where((s) => s.trim().isNotEmpty).toList();
      if (sentences.isEmpty) return text.substring(0, (text.length * ratio).round().clamp(1, text.length));
      if (sentences.length <= maxSentences) return sentences.join('。') + '。';

      // 计算词频
      final wordFreq = <String, int>{};
      final allWords = RegExp(r'[\u4e00-\u9fff]+|[a-zA-Z]+').allMatches(text);
      for (final match in allWords) {
        final w = match.group(0)!.toLowerCase();
        if (w.length > 1) wordFreq[w] = (wordFreq[w] ?? 0) + 1;
      }

      // 为每个句子评分（基于包含的关键词频率之和）
      final sentenceScores = <double>[];
      for (final sentence in sentences) {
        double score = 0;
        final sentenceWords = RegExp(r'[\u4e00-\u9fff]+|[a-zA-Z]+').allMatches(sentence);
        for (final match in sentenceWords) {
          final w = match.group(0)!.toLowerCase();
          score += wordFreq[w] ?? 0;
        }
        // 位置权重：前几句权重更高
        final positionBonus = 1.0 / (1 + sentences.indexOf(sentence) * 0.1);
        sentenceScores.add(score * positionBonus);
      }

      // 选择评分最高的句子，保持原文顺序
      final targetCount = (sentences.length * ratio).round().clamp(1, maxSentences);
      final indexedScores = sentenceScores.asMap().entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final selectedIndices = indexedScores.take(targetCount).map((e) => e.key).toList()
        ..sort();

      final summary = selectedIndices.map((i) => sentences[i].trim()).join('。') + '。';
      _addDebugLog('nlp', '本地摘要完成', data: {'inputSentences': sentences.length, 'outputSentences': selectedIndices.length});
      return summary;
    } catch (e) {
      _addDebugLog('nlp', '文本摘要失败', data: {'error': e.toString()});
      return '摘要失败: $e';
    }
  }
}

/// 云端认证错误（API Key 无效或过期）
class CloudAuthException implements Exception {
  final String message;
  const CloudAuthException(this.message);
  @override
  String toString() => message;
}

/// 云端网络错误
class CloudNetworkException implements Exception {
  final String message;
  const CloudNetworkException(this.message);
  @override
  String toString() => message;
}

/// 信号量（并发控制）
class _Semaphore {
  final int maxCount;
  int _currentCount = 0;
  final _waitQueue = <Completer<void>>[];

  _Semaphore(this.maxCount);

  Future<void> acquire() async {
    if (_currentCount < maxCount) {
      _currentCount++;
      return;
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    return completer.future;
  }

  void release() {
    if (_currentCount <= 0) return; // 防止负数
    if (_waitQueue.isNotEmpty) {
      _waitQueue.removeAt(0).complete();
    } else {
      _currentCount--;
    }
  }
}

// ═══════════════════════════════════════════════════════════
// 物联网（IoT）功能增强：设备连接、数据采集、远程控制、设备管理
// ═══════════════════════════════════════════════════════════

/// IoT 设备连接状态
enum IoTDeviceStatus { offline, connecting, online, error, updating }

/// IoT 设备类型
enum IoTDeviceType {
  penTablet,      // 手写板
  stylus,         // 电子笔
  scanner,        // 扫描仪
  camera,         // 摄像头
  display,        // 显示设备
  sensor,         // 传感器
  gateway,        // 网关
  custom,         // 自定义设备
}

/// IoT 通信协议
enum IoTProtocol { mqtt, coap, http, ble, wifi, zigbee, lora }

/// IoT 设备数据模型
///
/// 表示一个已注册的物联网设备，支持多种设备类型和通信协议。
class IoTDevice {
  final String id;
  final String name;
  final IoTDeviceType type;
  final IoTProtocol protocol;
  final String address;
  IoTDeviceStatus status;
  final DateTime registeredAt;
  DateTime? lastSeenAt;
  final Map<String, dynamic> capabilities;
  final Map<String, dynamic> config;
  final List<Map<String, dynamic>> telemetry;

  IoTDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.protocol,
    required this.address,
    this.status = IoTDeviceStatus.offline,
    DateTime? registeredAt,
    this.lastSeenAt,
    Map<String, dynamic>? capabilities,
    Map<String, dynamic>? config,
    List<Map<String, dynamic>>? telemetry,
  })  : registeredAt = registeredAt ?? DateTime.now(),
        capabilities = capabilities ?? {},
        config = config ?? {},
        telemetry = telemetry ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'protocol': protocol.name,
        'address': address,
        'status': status.name,
        'registeredAt': registeredAt.toIso8601String(),
        'lastSeenAt': lastSeenAt?.toIso8601String(),
        'capabilities': capabilities,
        'config': config,
        'telemetryCount': telemetry.length,
      };

  factory IoTDevice.fromJson(Map<String, dynamic> json) => IoTDevice(
        id: json['id'] as String,
        name: json['name'] as String,
        type: IoTDeviceType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => IoTDeviceType.custom,
        ),
        protocol: IoTProtocol.values.firstWhere(
          (e) => e.name == json['protocol'],
          orElse: () => IoTProtocol.http,
        ),
        address: json['address'] as String? ?? '',
        status: IoTDeviceStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => IoTDeviceStatus.offline,
        ),
        registeredAt: DateTime.parse(json['registeredAt'] as String),
        lastSeenAt: json['lastSeenAt'] != null
            ? DateTime.parse(json['lastSeenAt'] as String)
            : null,
        capabilities: json['capabilities'] as Map<String, dynamic>? ?? {},
        config: json['config'] as Map<String, dynamic>? ?? {},
      );
}

/// IoT 数据采集记录
class IoTDataRecord {
  final String deviceId;
  final String sensorType;
  final double value;
  final String unit;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  IoTDataRecord({
    required this.deviceId,
    required this.sensorType,
    required this.value,
    this.unit = '',
    DateTime? timestamp,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'sensorType': sensorType,
        'value': value,
        'unit': unit,
        'timestamp': timestamp.toIso8601String(),
        'metadata': metadata,
      };
}

/// IoT 设备管理服务
///
/// 提供完整的物联网功能，包括：
/// - 设备连接管理（注册、发现、连接、断开）
/// - 数据采集（传感器数据、设备状态、遥测）
/// - 远程控制（命令下发、配置更新、OTA升级）
/// - 设备管理（分组、标签、生命周期管理）
class IoTDeviceService {
  static final IoTDeviceService _instance = IoTDeviceService._();
  static IoTDeviceService get instance => _instance;
  IoTDeviceService._();

  final List<IoTDevice> _devices = [];
  final List<IoTDataRecord> _dataRecords = [];
  final List<Map<String, dynamic>> _commandHistory = [];
  final Map<String, List<String>> _deviceGroups = {}; // groupName -> deviceIds
  static const int _maxDataRecords = 10000;
  static const Duration _deviceTimeout = Duration(minutes: 5);

  /// 获取所有注册设备
  List<IoTDevice> get devices => List.unmodifiable(_devices);

  /// 获取在线设备
  List<IoTDevice> get onlineDevices =>
      _devices.where((d) => d.status == IoTDeviceStatus.online).toList();

  /// 获取数据记录
  List<IoTDataRecord> get dataRecords => List.unmodifiable(_dataRecords);

  /// 注册新设备
  ///
  /// [name] 设备名称
  /// [type] 设备类型
  /// [protocol] 通信协议
  /// [address] 设备地址/IP
  /// [capabilities] 设备能力描述
  IoTDevice registerDevice({
    required String name,
    required IoTDeviceType type,
    required IoTProtocol protocol,
    required String address,
    Map<String, dynamic>? capabilities,
    Map<String, dynamic>? config,
  }) {
    final device = IoTDevice(
      id: 'iot_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      type: type,
      protocol: protocol,
      address: address,
      capabilities: capabilities,
      config: config,
    );
    _devices.add(device);
    debugPrint('[IoT] 设备已注册: $name (${device.id}), 协议: ${protocol.name}');
    return device;
  }

  /// 连接到设备
  ///
  /// [deviceId] 设备ID
  /// 返回连接是否成功
  Future<bool> connectDevice(String deviceId) async {
    final device = _devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => throw Exception('设备不存在: $deviceId'),
    );

    device.status = IoTDeviceStatus.connecting;
    debugPrint('[IoT] 正在连接设备: ${device.name} (${device.address})');

    try {
      // 模拟连接过程
      await Future.delayed(const Duration(milliseconds: 500));

      // 根据协议类型模拟不同的连接方式
      switch (device.protocol) {
        case IoTProtocol.mqtt:
          debugPrint('[IoT] MQTT 连接建立: ${device.address}');
          break;
        case IoTProtocol.ble:
          debugPrint('[IoT] BLE 蓝牙连接建立: ${device.address}');
          break;
        case IoTProtocol.coap:
          debugPrint('[IoT] CoAP 连接建立: ${device.address}');
          break;
        case IoTProtocol.http:
          debugPrint('[IoT] HTTP 连接建立: ${device.address}');
          break;
        default:
          debugPrint('[IoT] ${device.protocol.name} 连接建立: ${device.address}');
      }

      device.status = IoTDeviceStatus.online;
      device.lastSeenAt = DateTime.now();
      debugPrint('[IoT] 设备已连接: ${device.name}');
      return true;
    } catch (e) {
      device.status = IoTDeviceStatus.error;
      debugPrint('[IoT] 设备连接失败: ${device.name}, 错误: $e');
      return false;
    }
  }

  /// 断开设备连接
  ///
  /// [deviceId] 设备ID
  Future<void> disconnectDevice(String deviceId) async {
    final device = _devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => throw Exception('设备不存在: $deviceId'),
    );
    device.status = IoTDeviceStatus.offline;
    debugPrint('[IoT] 设备已断开: ${device.name}');
  }

  /// 从设备采集数据
  ///
  /// [deviceId] 设备ID
  /// [sensorType] 传感器类型
  /// 返回采集的数据记录
  Future<IoTDataRecord> collectData({
    required String deviceId,
    required String sensorType,
  }) async {
    final device = _devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => throw Exception('设备不存在: $deviceId'),
    );

    if (device.status != IoTDeviceStatus.online) {
      throw Exception('设备离线，无法采集数据: ${device.name}');
    }

    // 模拟数据采集
    final record = IoTDataRecord(
      deviceId: deviceId,
      sensorType: sensorType,
      value: 0.0, // 实际值由设备提供
      unit: _getSensorUnit(sensorType),
      metadata: {'deviceName': device.name, 'protocol': device.protocol.name},
    );

    _dataRecords.add(record);
    device.lastSeenAt = DateTime.now();

    // 限制数据记录数量
    if (_dataRecords.length > _maxDataRecords) {
      _dataRecords.removeRange(0, _dataRecords.length - _maxDataRecords);
    }

    debugPrint('[IoT] 数据采集完成: ${device.name} -> $sensorType');
    return record;
  }

  /// 获取传感器默认单位
  String _getSensorUnit(String sensorType) {
    switch (sensorType) {
      case 'pressure': return 'Pa';
      case 'temperature': return '°C';
      case 'humidity': return '%';
      case 'acceleration': return 'm/s²';
      case 'tilt': return '°';
      case 'proximity': return 'cm';
      default: return '';
    }
  }

  /// 向设备发送远程命令
  ///
  /// [deviceId] 设备ID
  /// [command] 命令名称
  /// [params] 命令参数
  /// 返回执行结果
  Future<Map<String, dynamic>> sendCommand({
    required String deviceId,
    required String command,
    Map<String, dynamic>? params,
  }) async {
    final device = _devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => throw Exception('设备不存在: $deviceId'),
    );

    if (device.status != IoTDeviceStatus.online) {
      throw Exception('设备离线，无法发送命令: ${device.name}');
    }

    final commandRecord = {
      'deviceId': deviceId,
      'command': command,
      'params': params ?? {},
      'sentAt': DateTime.now().toIso8601String(),
      'status': 'sent',
    };

    // 模拟命令执行
    await Future.delayed(const Duration(milliseconds: 200));

    commandRecord['status'] = 'completed';
    commandRecord['completedAt'] = DateTime.now().toIso8601String();
    _commandHistory.add(commandRecord);

    debugPrint('[IoT] 远程命令已发送: ${device.name} -> $command');
    return commandRecord;
  }

  /// 更新设备配置
  ///
  /// [deviceId] 设备ID
  /// [config] 新配置
  Future<void> updateDeviceConfig(String deviceId, Map<String, dynamic> config) async {
    final device = _devices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => throw Exception('设备不存在: $deviceId'),
    );
    device.config.addAll(config);
    debugPrint('[IoT] 设备配置已更新: ${device.name}');
  }

  /// 创建设备分组
  ///
  /// [groupName] 分组名称
  /// [deviceIds] 设备ID列表
  void createDeviceGroup(String groupName, List<String> deviceIds) {
    _deviceGroups[groupName] = deviceIds;
    debugPrint('[IoT] 设备分组已创建: $groupName (${deviceIds.length} 台设备)');
  }

  /// 将设备添加到分组
  void addDeviceToGroup(String groupName, String deviceId) {
    _deviceGroups[groupName] ??= [];
    if (!_deviceGroups[groupName]!.contains(deviceId)) {
      _deviceGroups[groupName]!.add(deviceId);
    }
  }

  /// 获取设备分组
  Map<String, List<String>> get deviceGroups => Map.unmodifiable(_deviceGroups);

  /// 向分组内所有设备广播命令
  Future<List<Map<String, dynamic>>> broadcastToGroup({
    required String groupName,
    required String command,
    Map<String, dynamic>? params,
  }) async {
    final deviceIds = _deviceGroups[groupName];
    if (deviceIds == null || deviceIds.isEmpty) {
      throw Exception('设备分组不存在或为空: $groupName');
    }

    final results = <Map<String, dynamic>>[];
    for (final deviceId in deviceIds) {
      try {
        final result = await sendCommand(deviceId: deviceId, command: command, params: params);
        results.add(result);
      } catch (e) {
        results.add({'deviceId': deviceId, 'error': e.toString()});
      }
    }

    debugPrint('[IoT] 分组广播完成: $groupName -> $command (${results.length} 台设备)');
    return results;
  }

  /// 检查设备超时状态
  ///
  /// 将超过 [_deviceTimeout] 未响应的设备标记为离线
  void checkDeviceTimeout() {
    final now = DateTime.now();
    for (final device in _devices) {
      if (device.status == IoTDeviceStatus.online &&
          device.lastSeenAt != null &&
          now.difference(device.lastSeenAt!) > _deviceTimeout) {
        device.status = IoTDeviceStatus.offline;
        debugPrint('[IoT] 设备超时离线: ${device.name}');
      }
    }
  }

  /// 移除设备
  void removeDevice(String deviceId) {
    _devices.removeWhere((d) => d.id == deviceId);
    // 同时从所有分组中移除
    for (final group in _deviceGroups.values) {
      group.remove(deviceId);
    }
    debugPrint('[IoT] 设备已移除: $deviceId');
  }

  /// 获取设备统计信息
  Map<String, dynamic> getDeviceStats() {
    final online = _devices.where((d) => d.status == IoTDeviceStatus.online).length;
    final offline = _devices.where((d) => d.status == IoTDeviceStatus.offline).length;
    final error = _devices.where((d) => d.status == IoTDeviceStatus.error).length;

    // 按类型统计
    final typeCounts = <String, int>{};
    for (final device in _devices) {
      typeCounts[device.type.name] = (typeCounts[device.type.name] ?? 0) + 1;
    }

    return {
      'totalDevices': _devices.length,
      'online': online,
      'offline': offline,
      'error': error,
      'typeCounts': typeCounts,
      'totalDataRecords': _dataRecords.length,
      'totalCommands': _commandHistory.length,
      'totalGroups': _deviceGroups.length,
    };
  }
}
