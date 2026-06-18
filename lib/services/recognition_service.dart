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
  static const String _prefKeyModel = 'ocr_model';
  static const String _prefKeyCustomModel = 'ocr_custom_model';

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

      // 预处理组合列表：先确保灰度，再尝试不同增强策略
      // 灰度 → 原始 / 灰度 → 对比度 / 灰度 → 锐化 / 灰度 → 对比度+二值化
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
        '灰度+对比度+二值化': (src) {
          final gray = img.grayscale(src);
          final enhanced = img.adjustColor(gray, contrast: 1.5, brightness: 1.1);
          return _binarize(enhanced);
        },
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

          final rawResult = await _recognizeFromImage(processed);
          final result = _validateResult(rawResult);
          if (result != null) {
            debugPrint('ML Kit 识别: ✓ 第${attempt}次成功 (放大=${targetSize == 0 ? "原图" : "${base.width}x${base.height}"}, 预处理=$label), 字符="$result"');
            return result;
          }
          if (rawResult != null && rawResult.isNotEmpty) {
            debugPrint('ML Kit 识别: 过滤非目标字符 "$rawResult" (U+${rawResult.codeUnitAt(0).toRadixString(16)})');
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

    // 两轮 prompt：首轮常规，重试时加强语气
    final prompts = [
      '这是一个手写汉字的图片，请识别图片中的汉字。只输出一个汉字，不要输出其他任何内容。如果识别不出，输出?',
      '请仔细识别这张手写汉字图片中的汉字。只输出一个完整的汉字，不要输出标点、假名、偏旁或其他文字。如果无法确定，输出?',
    ];

    for (int attempt = 0; attempt < prompts.length; attempt++) {
      try {
        final base64Image = base64Encode(compressedBytes);

        debugPrint('云端识别: 第${attempt + 1}次请求');

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
        } else {
          final statusCode = response.statusCode;
          if (statusCode == 401 || statusCode == 403) {
            debugPrint('云端识别认证失败 ($statusCode): API Key 无效或已过期');
            throw const CloudAuthException('认证失败: API Key 无效或已过期，请检查后重试');
          }
          debugPrint('云端识别 HTTP $statusCode: ${response.body}');
        }
      } on CloudAuthException {
        rethrow;
      } catch (e) {
        debugPrint('云端识别失败 (第${attempt + 1}次): $e');
      }
    }

    debugPrint('云端识别: 所有尝试均未返回有效字符');
    return null;
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
