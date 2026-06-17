import 'dart:convert';
import 'package:crypto/crypto.dart';

/// API Key 哈希混淆存储
/// Key 拆分后用 SHA256(salt+index) 做 XOR 加密
/// 运行时解密还原，不明文存储
class ApiKeyProvider {
  static const _salt = 'writefont2024';

  // 加密后的分段字节数组
  static const _s0 = [57, 161, 202, 181, 103, 243, 96, 97, 147, 141, 141, 251];
  static const _s1 = [111, 49, 117, 186, 3, 0, 194, 157, 138, 63, 20, 101];
  static const _s2 = [209, 120, 73, 18, 132, 147, 167, 200, 135, 127, 189, 136];
  static const _s3 = [144, 146, 62, 30, 93, 213, 6, 172, 9, 156, 135, 77, 167, 12, 16];

  static const _segments = [_s0, _s1, _s2, _s3];

  static String? _cached;

  /// 获取 SiliconFlow API Key
  static String get siliconFlowKey => getKey();

  static String getKey() {
    if (_cached != null) return _cached!;
    final buf = StringBuffer();
    for (int i = 0; i < _segments.length; i++) {
      final hashInput = utf8.encode('$_salt$i');
      final keyStream = sha256.convert(hashInput).bytes;
      final seg = _segments[i];
      for (int j = 0; j < seg.length; j++) {
        buf.writeCharCode(seg[j] ^ keyStream[j % keyStream.length]);
      }
    }
    _cached = buf.toString();
    return _cached!;
  }
}
