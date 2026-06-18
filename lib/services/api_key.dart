import 'package:flutter/services.dart';

/// API Key 哈希混淆存储
/// Key 拆分后用 SHA256(salt+index) 做 XOR 加密
/// 解密逻辑在 Native C 层 (NDK)，通过 MethodChannel 调用
class ApiKeyProvider {
  static const _channel = MethodChannel('com.writefont/native_key');
  static String? _cached;

  /// 获取 SiliconFlow API Key
  static String get siliconFlowKey => _cached ?? '';

  static Future<String> getKey() async {
    if (_cached != null) return _cached!;
    try {
      final String key = await _channel.invokeMethod('getKey');
      _cached = key;
      return key;
    } catch (e) {
      // Native 调用失败时返回空（非 Android 平台等场景）
      return '';
    }
  }
}
