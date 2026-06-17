import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'api_key.dart';

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

  // ===== 图片预处理辅助方法 =====

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

  /// 对比度增强（复用已有 adjustColor API，与 image_processor.dart 一致）
  img.Image _enhanceContrast(img.Image src) {
    return img.adjustColor(src, contrast: 1.5, brightness: 1.1);
  }

  /// 二值化（Otsu 自动阈值）
  img.Image _binarize(img.Image src) {
    final gray = img.grayscale(src);
    // 计算 Otsu 阈值
    final histogram = List<int>.filled(256, 0);
    for (int y = 0; y < gray.height; y++) {
      for (int x = 0; x < gray.width; x++) {
        histogram[gray.getPixel(x, y).r.toInt()]++;
      }
    }
    final totalPixels = gray.width * gray.height;
    int sum = 0;
    for (int i = 0; i < 256; i++) {
      sum += i * histogram[i];
    }
    int sumB = 0;
    int wB = 0;
    double maxVariance = 0;
    int threshold = 0;
    for (int i = 0; i < 256; i++) {
      wB += histogram[i];
      if (wB == 0) continue;
      final wF = totalPixels - wB;
      if (wF == 0) break;
      sumB += i * histogram[i];
      final mB = sumB / wB;
      final mF = (sum - sumB) / wF;
      final variance = wB * wF * (mB - mF) * (mB - mF);
      if (variance > maxVariance) {
        maxVariance = variance;
        threshold = i;
      }
    }
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

  /// 本地 ML Kit 识别（多级预处理 + 重试策略）
  Future<String?> _recognizeLocal(Uint8List imageBytes) async {
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return null;

      final w = decoded.width;
      final h = decoded.height;
      final maxDim = w > h ? w : h;
      debugPrint('ML Kit 识别: 原始图片 ${w}x$h，最大边 $maxDim');

      // 根据图片大小分级，定义放大目标尺寸序列
      List<int> upscaleTargets;
      if (maxDim < 50) {
        // 单字级别：放大到 400→600→800
        upscaleTargets = [400, 600, 800];
      } else if (maxDim < 100) {
        // 小字：放大到 300→500→700
        upscaleTargets = [300, 500, 700];
      } else if (maxDim < 200) {
        // 中等：放大到 200→400
        upscaleTargets = [200, 400];
      } else {
        // 大图：不放大，只做预处理
        upscaleTargets = [0]; // 0 表示不放大，用原图
      }

      debugPrint('ML Kit 识别: 分级策略 targets=$upscaleTargets');

      // 预处理组合列表：原始、锐化、对比度增强、二值化
      final preprocessors = <String, img.Image Function(img.Image)>{
        '原始': (img) => img,
        '锐化': _sharpen,
        '对比度增强': _enhanceContrast,
        '二值化': _binarize,
      };

      int attempt = 0;

      // 对每个放大级别 × 每种预处理组合尝试识别
      for (final targetSize in upscaleTargets) {
        // 确定当前要处理的图片
        img.Image base;
        if (targetSize == 0) {
          base = decoded;
        } else {
          // 等比放大到目标尺寸（以最大边为准）
          final scale = targetSize / maxDim;
          final newW = (w * scale).round();
          final newH = (h * scale).round();
          base = img.copyResize(decoded, width: newW, height: newH,
              interpolation: img.Interpolation.cubic);
          debugPrint('ML Kit 识别: 放大到 ${base.width}x${base.height}');
        }

        for (final entry in preprocessors.entries) {
          attempt++;
          final label = entry.key;
          final preprocessor = entry.value;
          final processed = preprocessor(base);

          debugPrint('ML Kit 识别: 第${attempt}次尝试 | 放大=${targetSize == 0 ? "原图" : "${base.width}x${base.height}"} | 预处理=$label');

          final result = await _recognizeFromImage(processed);
          if (result != null && result.isNotEmpty) {
            debugPrint('ML Kit 识别: ✓ 第${attempt}次成功 (放大=${targetSize == 0 ? "原图" : "${base.width}x${base.height}"}, 预处理=$label)');
            return result;
          }
          debugPrint('ML Kit 识别: ✗ 第${attempt}次未识别到文字');
        }
      }

      debugPrint('ML Kit 识别: 所有${attempt}次尝试均未识别到文字');
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
      tempFile = File('${tempDir.path}/mlkit_${DateTime.now().millisecondsSinceEpoch}.png');
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
                return String.fromCharCodes(text.runes.take(1));
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
                  'text': '请识别图片中的汉字，只输出识别到的汉字，不要输出其他内容。如果识别不出，输出空。',
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
                // 优先提取第一个中文字符
                final chineseMatch = RegExp(r'[一-鿿]').firstMatch(content);
                if (chineseMatch != null) {
                  return chineseMatch.group(0);
                }
                // 否则取最后一个字符（API 通常在末尾输出识别结果）
                return String.fromCharCodes(content.runes.toList().reversed.take(1));
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
