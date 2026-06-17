import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// AI 字符识别服务
/// 通过后端 API 进行 OCR 识别，支持降级为顺序分配
class RecognitionService {
  static const String _prefKeyServerUrl = 'recognition_server_url';
  static const String _apiEndpoint = '/api/v1/recognize';
  static const Duration _timeout = Duration(seconds: 10);

  static RecognitionService? _instance;
  static RecognitionService get instance => _instance ??= RecognitionService._();

  RecognitionService._();

  String? _serverUrl;

  /// 获取当前配置的服务器地址
  Future<String?> getServerUrl() async {
    if (_serverUrl != null) return _serverUrl;
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString(_prefKeyServerUrl);
    return _serverUrl;
  }

  /// 保存服务器地址
  Future<void> setServerUrl(String? url) async {
    _serverUrl = url;
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.isEmpty) {
      await prefs.remove(_prefKeyServerUrl);
    } else {
      await prefs.setString(_prefKeyServerUrl, url);
    }
  }

  /// 检查服务器是否可用
  Future<bool> isServerAvailable() async {
    final url = await getServerUrl();
    if (url == null || url.isEmpty) return false;

    try {
      final uri = Uri.parse('$url/api/v1/health');
      final response = await http.get(uri).timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 识别单个字符图片
  /// 返回识别出的字符，识别失败返回 null
  Future<String?> recognizeCharacter(Uint8List imageBytes) async {
    final serverUrl = await getServerUrl();
    if (serverUrl == null || serverUrl.isEmpty) return null;

    try {
      final uri = Uri.parse('$serverUrl$_apiEndpoint');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: 'char.png',
        ));

      final streamedResponse = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data.containsKey('character')) {
          final char = data['character'] as String?;
          if (char != null && char.isNotEmpty) {
            return char;
          }
        }
      }
    } catch (_) {
      // 识别失败，返回 null 让调用方降级处理
    }
    return null;
  }

  /// 批量识别字符图片
  /// 返回每个图片对应的字符，识别失败的位置返回 null
  Future<List<String?>> recognizeBatch(List<Uint8List> images) async {
    final serverUrl = await getServerUrl();
    if (serverUrl == null || serverUrl.isEmpty) {
      return List.filled(images.length, null);
    }

    try {
      final uri = Uri.parse('$serverUrl/api/v1/recognize-batch');
      final request = http.MultipartRequest('POST', uri);
      for (int i = 0; i < images.length; i++) {
        request.files.add(http.MultipartFile.fromBytes(
          'images',
          images[i],
          filename: 'char_$i.png',
        ));
      }

      final streamedResponse = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data.containsKey('characters')) {
          final chars = data['characters'] as List?;
          if (chars != null && chars.length == images.length) {
            return chars.map((c) => c as String?).toList();
          }
        }
      }
    } catch (_) {
      // 批量识别失败
    }
    return List.filled(images.length, null);
  }

  /// 清除缓存
  void clearCache() {
    _serverUrl = null;
  }
}
