import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RecognizeService {
  static const String _prefKey = 'recognize_server_url';
  static const String defaultUrl = 'http://192.168.1.100:8080';
  static const int _timeoutSeconds = 10;
  static const int _maxConcurrent = 3;

  static Future<String> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefKey) ?? defaultUrl;
  }

  static Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, url);
  }

  /// 验证 URL 格式（防止 SSRF）
  static bool isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (!['http', 'https'].contains(uri.scheme)) return false;
      if (uri.host.isEmpty) return false;
      // 阻止内网地址（可选，注释掉以便本地开发）
      // if (uri.host.startsWith('192.168.') || uri.host.startsWith('10.') || uri.host == 'localhost') return false;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 识别单个字符
  static Future<RecognizeResult> recognizeSingle(
    Uint8List imageBytes, {
    String? serverUrl,
  }) async {
    final url = serverUrl ?? await getServerUrl();

    // 验证 URL
    if (!isValidUrl(url)) {
      return RecognizeResult(char: '?', confidence: 0, success: false, error: '无效的服务器地址');
    }

    final base64Image = base64Encode(imageBytes);

    try {
      final response = await http
          .post(
            Uri.parse('$url/api/recognize'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'image': base64Image,
              'charset': '常用字',
            }),
          )
          .timeout(const Duration(seconds: _timeoutSeconds));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return RecognizeResult(
          char: data['char'] ?? '?',
          confidence: (data['confidence'] ?? 0.0).toDouble(),
          success: true,
        );
      }
      return RecognizeResult(char: '?', confidence: 0, success: false, error: '服务器返回 ${response.statusCode}');
    } on TimeoutException {
      return RecognizeResult(char: '?', confidence: 0, success: false, error: '识别超时');
    } catch (e) {
      return RecognizeResult(char: '?', confidence: 0, success: false, error: e.toString());
    }
  }

  /// 批量识别字符（带并发控制）
  static Future<List<RecognizeResult>> recognizeBatch(
    List<Uint8List> images, {
    String? serverUrl,
    void Function(int current, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final results = List<RecognizeResult>.filled(
      images.length,
      RecognizeResult(char: '?', confidence: 0, success: false),
    );

    int completed = 0;
    final semaphore = _Semaphore(_maxConcurrent);

    final futures = <Future>[];
    for (int i = 0; i < images.length; i++) {
      // 检查取消
      if (cancelToken?.isCancelled ?? false) break;

      final index = i;
      futures.add(() async {
        await semaphore.acquire();
        try {
          if (cancelToken?.isCancelled ?? false) return;
          results[index] = await recognizeSingle(
            images[index],
            serverUrl: serverUrl,
          );
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
}

class RecognizeResult {
  final String char;
  final double confidence;
  final bool success;
  final String? error;

  RecognizeResult({
    required this.char,
    required this.confidence,
    required this.success,
    this.error,
  });
}

/// 取消令牌
class CancelToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;
  void cancel() => _isCancelled = true;
}

/// 信号量实现（并发控制）
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
    if (_waitQueue.isNotEmpty) {
      _waitQueue.removeAt(0).complete();
    } else {
      _currentCount--;
    }
  }
}
