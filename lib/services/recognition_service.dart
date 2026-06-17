import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// OCR 识别服务
/// 默认：本地 ML Kit 离线识别（免费，无需网络）
/// 可选：云端 API（用户填自己的 API 地址 + Key）
class RecognitionService {
  // SharedPreferences keys
  static const String _prefKeyUseCloud = 'ocr_use_cloud';
  static const String _prefKeyCloudUrl = 'ocr_cloud_url';
  static const String _prefKeyCloudKey = 'ocr_cloud_key';

  // DeepSeek-OCR (硅基流动) 默认配置
  static const String defaultCloudUrl = 'https://api.siliconflow.cn/v1/chat/completions';
  static const String defaultModel = 'deepseek-ai/DeepSeek-OCR';
  static const String cloudDisplayName = 'DeepSeek-OCR（硅基流动免费）';

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
    if (_cloudKey != null) return _cloudKey;
    _cloudKey = await _secureStorage.read(key: _prefKeyCloudKey);
    // 迁移：如果安全存储中没有，但 SharedPreferences 中有旧的明文 Key，迁移过来
    if (_cloudKey == null || _cloudKey!.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final oldKey = prefs.getString(_prefKeyCloudKey);
      if (oldKey != null && oldKey.isNotEmpty) {
        await _secureStorage.write(key: _prefKeyCloudKey, value: oldKey);
        await prefs.remove(_prefKeyCloudKey);
        _cloudKey = oldKey;
      }
    }
    return _cloudKey;
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

  /// 识别单个字符图片
  Future<String?> recognizeCharacter(Uint8List imageBytes, {bool? forceUseCloud}) async {
    final useCloud = forceUseCloud ?? await getUseCloud();

    if (useCloud) {
      return _recognizeCloud(imageBytes);
    } else {
      return _recognizeLocal(imageBytes);
    }
  }

  /// 批量识别字符图片（带并发控制和进度回调）
  Future<List<String?>> recognizeBatch(
    List<Uint8List> images, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final results = List<String?>.filled(images.length, null);
    final useCloud = await getUseCloud();

    int completed = 0;
    final semaphore = _Semaphore(_maxConcurrent);
    final futures = <Future>[];

    for (int i = 0; i < images.length; i++) {
      final index = i;
      futures.add(() async {
        await semaphore.acquire();
        try {
          if (useCloud) {
            results[index] = await _recognizeCloud(images[index]);
          } else {
            results[index] = await _recognizeLocal(images[index]);
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

  /// 本地 ML Kit 识别
  Future<String?> _recognizeLocal(Uint8List imageBytes) async {
    try {
      // 解码图片获取实际尺寸
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return null;

      final width = decoded.width;
      final height = decoded.height;

      // 转换为 NV21 格式（ML Kit Android 需要）
      final nv21Bytes = _convertToNV21(decoded);

      final inputImage = InputImage.fromBytes(
        bytes: nv21Bytes,
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: width,
        ),
      );

      final recognizer = _getMlKitRecognizer();
      final recognizedText = await recognizer.processImage(inputImage);

      if (recognizedText.text.isNotEmpty) {
        for (final block in recognizedText.blocks) {
          for (final line in block.lines) {
            for (final element in line.elements) {
              final text = element.text.trim();
              if (text.isNotEmpty && text.runes.isNotEmpty) {
                return String.fromCharCodes(text.runes.take(1));
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('ML Kit 识别失败: $e');
    }
    return null;
  }

  /// 将图片转换为 NV21 格式
  Uint8List _convertToNV21(img.Image image) {
    final width = image.width;
    final height = image.height;
    final yuvSize = width * height * 3 ~/ 2;
    final nv21 = Uint8List(yuvSize);

    int yIndex = 0;
    int uvIndex = width * height;

    for (int j = 0; j < height; j++) {
      for (int i = 0; i < width; i++) {
        final pixel = image.getPixel(i, j);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        // RGB to YUV
        final y = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
        final u = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
        final v = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;

        nv21[yIndex++] = y.clamp(0, 255);

        if (j % 2 == 0 && i % 2 == 0) {
          nv21[uvIndex++] = v.clamp(0, 255);
          nv21[uvIndex++] = u.clamp(0, 255);
        }
      }
    }

    return nv21;
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
  Future<String?> _recognizeCloud(Uint8List imageBytes) async {
    final cloudUrl = await getCloudUrl();
    final cloudKey = await getCloudKey();

    if (cloudUrl.isEmpty) return null;
    if (!_isValidPublicUrl(cloudUrl)) {
      debugPrint('云端识别: URL 不合法或为私有地址');
      return null;
    }

    try {
      final base64Image = base64Encode(imageBytes);

      final response = await http.post(
        Uri.parse(cloudUrl),
        headers: {
          'Content-Type': 'application/json',
          if (cloudKey != null && cloudKey.isNotEmpty) 'Authorization': 'Bearer $cloudKey',
        },
        body: jsonEncode({
          'model': defaultModel,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/png;base64,$base64Image',
                  },
                },
                {
                  'type': 'text',
                  'text': 'Free OCR.',
                },
              ],
            },
          ],
          'max_tokens': 1024,
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
              if (content != null && content.isNotEmpty && content.runes.isNotEmpty) {
                return String.fromCharCodes(content.runes.take(1));
              }
            }
          }
        }
      } else {
        final statusCode = response.statusCode;
        if (statusCode == 401 || statusCode == 403) {
          debugPrint('云端识别认证失败 ($statusCode): API Key 无效或已过期');
          throw const CloudAuthException('认证失败: API Key 无效或已过期，请检查后重试');
        }
        debugPrint('云端识别 HTTP $statusCode: ${response.body}');
      }
    } on CloudAuthException {
      rethrow; // 认证错误直接向上传播，让调用方显示友好提示
    } catch (e) {
      debugPrint('云端识别失败: $e');
    }
    return null;
  }

  /// 释放资源（应在 app 退出时调用）
  void dispose() {
    _mlKitRecognizer?.close();
    _mlKitRecognizer = null;
  }

  /// 清除配置缓存
  void clearCache() {
    _useCloud = null;
    _cloudUrl = null;
    _cloudKey = null;
  }
}

/// 云端认证错误（API Key 无效或过期）
class CloudAuthException implements Exception {
  final String message;
  const CloudAuthException(this.message);
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
