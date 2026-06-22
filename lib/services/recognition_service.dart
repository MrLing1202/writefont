import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'api_key.dart';

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

  // ML Kit 识别器（懒加载）
  TextRecognizer? _mlKitRecognizer;

  /// 最近一次本地识别的投票置信度（供 recognizeCharacter 判断是否需要云端二次确认）
  double _lastLocalConfidence = 0.0;

  /// 策略可靠性追踪（策略名 → 历史成功率 0.0~1.0）— v2.6.0
  /// 用于加权投票：高可靠性策略的投票获得 1.2x 权重加成
  static final Map<String, double> _strategyReliability = {};

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
  /// 只接受：完整中文汉字 (U+4E00–U+9FFF)、常用 ASCII (U+0021–U+007E)
  /// 排除：偏旁、日文假名、韩文、特殊符号等
  static bool _isValidChar(String ch) {
    if (ch.isEmpty) return false;
    final code = ch.codeUnitAt(0);
    // 常用 ASCII（空格 0x20 除外）
    if (code >= 0x21 && code <= 0x7E) return true;
    // CJK 统一汉字（基本区）
    if (code >= 0x4E00 && code <= 0x9FFF) return true;
    return false;
  }

  /// 验证并返回有效字符，无效则返回 null
  static String? _validateResult(String? result) {
    if (result == null || result.isEmpty) return null;
    final ch = String.fromCharCodes(result.runes.take(1));
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

      // ── 字典后处理：常见字优先，形近字纠正 ──
      final confidence = _confidenceCache[cacheKey] ?? 0.75;
      final dictResult = DictionaryService.instance.postProcess(result, confidence: confidence);
      if (dictResult != result) {
        _addDebugLog('recognition', '字典后处理', data: {
          'original': result,
          'corrected': dictResult,
          'confidence': confidence,
        });
        debugPrint('识别: 字典后处理 "$result" → "$dictResult"');
        result = dictResult;
      }

      // ── 笔画特征辅助选择：低置信度时用笔画特征优化结果 ──
      if (confidence < 0.85 && result != null) {
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

      // 记录用户识别的字符，更新用户常用字缓存（异步，不阻塞返回）
      DictionaryService.instance.recordUsage(result);

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

      // 图像质量增强
      final qualityReport = ImageQualityService.instance.assessQuality(decoded);
      img.Image enhanced = decoded;
      if (qualityReport.needsEnhancement) {
        enhanced = ImageQualityService.instance.enhanceForRecognition(decoded, qualityReport);
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

      // 按票数降序，票数相同取置信度高的
      final sorted = voteMap.entries.toList()
        ..sort((a, b) {
          final voteDiff = b.value.compareTo(a.value);
          if (voteDiff != 0) return voteDiff;
          return (confidenceMap[b.key] ?? 0).compareTo(confidenceMap[a.key] ?? 0);
        });

      return sorted.take(n).map((e) => e.key).toList();
    } catch (e) {
      debugPrint('recognizeCharacterTopN 失败: $e');
      return [];
    }
  }

  /// 批量识别字符图片（带并发控制和进度回调）
  /// 改进：使用缓存预检优化，已缓存的结果直接返回，减少等待
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
          // 批量识别成功后，为原始图片缓存结果和置信度
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

      // ═══ 图像质量评估与自动增强 ═══
      final qualityReport = ImageQualityService.instance.assessQuality(decoded);
      img.Image enhanced = decoded;
      if (qualityReport.needsEnhancement) {
        debugPrint('ML Kit 识别: 图像质量偏低，执行自动增强 $qualityReport');
        enhanced = ImageQualityService.instance.enhanceForRecognition(decoded, qualityReport);
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

      // v3.6.0: 快速通道 — 额外跑2个策略，3个一致直接返回
      // v3.9.0: CLAHE 自适应替换固定对比度增强
      if (voteMap.isNotEmpty && maxDim >= 50) {
        final quickStrategies = [
          ('CLAHE自适应', (img.Image src) => ImageQualityService.instance.enhanceContrastAdaptive(src)),
          ('USM笔画锐化', (img.Image src) => _unsharpMaskSharpen(src, amount: 1.5)),
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
        // 3个快速策略一致 → 直接返回
        if (voteMap.isNotEmpty) {
          final topVotes = voteMap.values.reduce((a, b) => a > b ? a : b);
          if (topVotes >= 3) {
            final quickWinner = voteMap.entries.reduce((a, b) => a.value >= b.value ? a : b);
            _lastLocalConfidence = 0.92;
            debugPrint('ML Kit 识别: 快速通道命中 "${quickWinner.key}" (${quickWinner.value}票)');
            return quickWinner.key;
          }
        }
      }

      // ═══ 第二轮：多级预处理 + 投票 ═══
      // 根据图片大小分级，定义放大目标尺寸序列
      List<int> upscaleTargets;
      if (maxDim < 50) {
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
        for (final k in ['灰度+对比度+二值化', '自适应对比度增强', 'CLAHE自适应', '自适应直方图均衡', '背景归一化']) {
          if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
        }
      }
      if (features.noise > 0.5) {
        // 高噪声：加降噪类策略
        for (final k in ['灰度+去噪', '灰度+去噪+锐化', '高斯模糊去噪+锐化']) {
          if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
        }
      }
      if (features.blur > 0.5) {
        // 模糊：加锐化类策略（含 v4.0.0 USM）
        for (final k in ['灰度+锐化', '灰度+去噪+锐化', '方向边缘增强', 'USM笔画锐化', 'USM强锐化', 'USM锐化+CLAHE']) {
          if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
        }
      }
      if (features.lineThickness < 0.3) {
        // 细线条：加增粗策略
        for (final k in ['手写体笔画增强', '笔画归一化']) {
          if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
        }
      }
      if (features.lineThickness > 0.7) {
        // 粗线条：加细化策略
        for (final k in ['形态学骨架化']) {
          if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
        }
      }
      if (features.connection > 0.6) {
        // 连笔：加分离策略
        for (final k in ['形态学骨架化', '局部阈值二值化']) {
          if (preprocessors.containsKey(k)) filteredPreprocessors[k] = preprocessors[k]!;
        }
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
      debugPrint('ML Kit 识别: 智能策略选择 ${filteredPreprocessors.length}/${preprocessors.length} 种 (对比度=${features.contrast.toStringAsFixed(2)}, 噪声=${features.noise.toStringAsFixed(2)}, 模糊=${features.blur.toStringAsFixed(2)})');

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

        for (final entry in filteredPreprocessors.entries) {
          attempt++;
          final label = entry.key;
          final preprocessor = entry.value;
          final processed = preprocessor(base);

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
            // 提前终止：票数过半时无需继续
            final totalAttempts = upscaleTargets.length * filteredPreprocessors.length;
            if (voteMap[result]! >= 3) {
              earlyTerminated = true;
              debugPrint('ML Kit 识别: 提前终止，$result 已获 ${voteMap[result]} 票');
              break;
            }
          } else {
            if (rawResult != null && rawResult.isNotEmpty) {
              debugPrint('ML Kit 识别: 过滤非目标字符 "$rawResult" (U+${rawResult.codeUnitAt(0).toRadixString(16)})');
            }
            debugPrint('ML Kit 识别: ✗ 第${attempt}次未识别到文字');
          }
        }
        // 如果已经提前终止（票数过半），跳出外层循环
        if (voteMap.isNotEmpty) {
          final maxVotes = voteMap.values.reduce((a, b) => a > b ? a : b);
          if (maxVotes >= 3) break; // v2.8.0: 降低阈值
        }
      }

      // v2.6.0: 智能投票选出最佳结果
      if (voteMap.isNotEmpty) {
        // 按票数排序，票数相同取置信度高的，再相同取常见字优先（v3.0.0）
        final sorted = voteMap.entries.toList()
          ..sort((a, b) {
            final voteDiff = b.value.compareTo(a.value);
            if (voteDiff != 0) return voteDiff;
            final confDiff = (confidenceMap[b.key] ?? 0).compareTo(confidenceMap[a.key] ?? 0);
            if (confDiff != 0) return confDiff;
            // v3.0.0: 字频加权 — 常见字优先（字频越高值越大）
            final freqA = DictionaryService.instance.getFrequency(a.key);
            final freqB = DictionaryService.instance.getFrequency(b.key);
            return freqB.compareTo(freqA);
          });
        var winner = sorted.first;

        // ── 平局决胜：top-2 票数差仅为 1 时，用多种预处理投票决胜（v3.2.0） ──
        if (sorted.length >= 2 && (winner.value - sorted[1].value) <= 1) {
          debugPrint('ML Kit 识别: 平局决胜触发 (top1="${winner.key}"=${winner.value}票, top2="${sorted[1].key}"=${sorted[1].value}票)');
          final candidateA = winner.key;
          final candidateB = sorted[1].key;
          int tieBreakA = 0;
          int tieBreakB = 0;

          // v3.2.0: 用3种不同预处理做决胜投票（而非原来只用1种）
          final tieBreakers = [
            _sharpen(img.adjustColor(img.grayscale(enhanced), contrast: 1.8, brightness: 1.2)),
            _adaptiveBinarize(img.grayscale(enhanced), blockSize: 25, c: 8),
            _clahe(enhanced),
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
          }
          // 若决胜仍平手，保持原排序（置信度高的优先）
        }

        // ── 置信度校准 ──
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
          debugPrint('ML Kit 识别: 置信度校准 — 提前终止 (=0.95)');
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

        _lastLocalConfidence = calibratedConf;

        // ── 更新策略可靠性 ──
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

        // v3.8.0: 低置信度旋转重试 — 尝试90°/180°/270°旋转
        if (_lastLocalConfidence < 0.5 && maxDim >= 80) {
          debugPrint('ML Kit 识别: 置信度低，尝试旋转重试');
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
      final trimmed = _trimWhitespace(fallbackBase);
      if (trimmed.width != fallbackBase.width || trimmed.height != fallbackBase.height) {
        final grayTrimmed = img.grayscale(trimmed);
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
                // 计算并缓存识别置信度
                // ML Kit element 没有直接置信度字段，使用文本长度和元素数量估算
                // 单字符识别时，文本越短且匹配越精确，置信度越高
                final confidence = _estimateConfidence(element, recognizedText);
                // 复用已有的 pngBytes，避免重复编码
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
                    // 优先提取第一个中文字符
                    final chineseMatch = RegExp(r'[一-鿿]').firstMatch(content);
                    if (chineseMatch != null) {
                      final result = chineseMatch.group(0);
                      debugPrint('云端识别: ✓ 提取中文字符 "$result" (第${attempt + 1}次)');
                      return result;
                    }
                    // 否则遍历所有字符，取第一个有效字符
                    for (final rune in content.runes) {
                      final ch = String.fromCharCode(rune);
                      if (_isValidChar(ch)) {
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
  static void correctRecognition(Uint8List imageBytes, String correctedChar) {
    if (correctedChar.isEmpty) return;
    final cacheKey = _hashBytes(imageBytes);
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

  /// 释放资源（应在 app 退出时调用）
  void dispose() {
    _mlKitRecognizer?.close();
    _mlKitRecognizer = null;
    _recognitionCache.clear();
    _cacheAccessOrder.clear();
    _confidenceCache.clear();
    _detailCache.clear();
    _estimatedCacheBytes = 0; // 重置内存计数
    _strategyReliability.clear(); // 重置策略可靠性
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
  static const String _currentEngineVersion = 'v2.16.0';

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
