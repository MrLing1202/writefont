import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// API Key 哈希混淆存储 + 隐私保护
///
/// Key 拆分后用 SHA256(salt+index) 做 XOR 加密
/// 解密逻辑在 Native C 层 (NDK)，通过 MethodChannel 调用
///
/// 增强功能：
/// - 隐私设置管理
/// - 数据收集说明
/// - 隐私政策显示
/// - 数据导出功能
class ApiKeyProvider {
  static const _channel = MethodChannel('com.writefont/native_key');
  static String? _cached;

  // ── 隐私设置 keys ──
  static const _keyAnalyticsEnabled = 'privacy_analytics_enabled';
  static const _keyCrashReportingEnabled = 'privacy_crash_reporting_enabled';
  static const _keyDataCollectionConsent = 'privacy_data_collection_consent';
  static const _keyPrivacyPolicyVersion = 'privacy_policy_version';

  /// 当前隐私政策版本号
  static const int currentPrivacyPolicyVersion = 1;

  /// 隐私政策 URL
  static const String privacyPolicyUrl = 'https://writefont.app/privacy';

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

  // ═══════════════════════════════════════════════════════════
  // 隐私设置管理
  // ═══════════════════════════════════════════════════════════

  /// 检查是否已同意数据收集
  static Future<bool> hasDataCollectionConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDataCollectionConsent) ?? false;
  }

  /// 设置数据收集同意状态
  static Future<void> setDataCollectionConsent(bool consented) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDataCollectionConsent, consented);
    // 如果不同意数据收集，同时关闭分析和崩溃报告
    if (!consented) {
      await setAnalyticsEnabled(false);
      await setCrashReportingEnabled(false);
    }
  }

  /// 检查分析数据收集是否启用
  static Future<bool> isAnalyticsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    // 需要同时有数据收集同意
    final consent = prefs.getBool(_keyDataCollectionConsent) ?? false;
    if (!consent) return false;
    return prefs.getBool(_keyAnalyticsEnabled) ?? false;
  }

  /// 设置分析数据收集开关
  static Future<void> setAnalyticsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAnalyticsEnabled, enabled);
  }

  /// 检查崩溃报告是否启用
  static Future<bool> isCrashReportingEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final consent = prefs.getBool(_keyDataCollectionConsent) ?? false;
    if (!consent) return false;
    return prefs.getBool(_keyCrashReportingEnabled) ?? false;
  }

  /// 设置崩溃报告开关
  static Future<void> setCrashReportingEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyCrashReportingEnabled, enabled);
  }

  /// 获取所有隐私设置的汇总
  static Future<Map<String, dynamic>> getPrivacySettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'dataCollectionConsent': prefs.getBool(_keyDataCollectionConsent) ?? false,
      'analyticsEnabled': prefs.getBool(_keyAnalyticsEnabled) ?? false,
      'crashReportingEnabled': prefs.getBool(_keyCrashReportingEnabled) ?? false,
      'privacyPolicyVersion': prefs.getInt(_keyPrivacyPolicyVersion) ?? 0,
    };
  }

  /// 检查隐私政策是否已确认（版本匹配时返回 true）
  static Future<bool> isPrivacyPolicyAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    final acceptedVersion = prefs.getInt(_keyPrivacyPolicyVersion) ?? 0;
    return acceptedVersion >= currentPrivacyPolicyVersion;
  }

  /// 确认隐私政策（记录当前版本号）
  static Future<void> acceptPrivacyPolicy() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPrivacyPolicyVersion, currentPrivacyPolicyVersion);
  }

  // ═══════════════════════════════════════════════════════════
  // 数据收集说明
  // ═══════════════════════════════════════════════════════════

  /// 获取应用收集的数据类型说明
  ///
  /// 返回结构化的数据收集说明，供隐私设置页面展示
  static List<Map<String, String>> getDataCollectionDescription() {
    return [
      {
        'category': '本地存储数据',
        'description': '项目数据（手写字体、字符图片）存储在设备本地，不会上传到服务器。',
        'type': 'required',
      },
      {
        'category': '云同步数据',
        'description': '如果您启用云同步，项目数据将通过加密连接上传到 Supabase 云端存储。仅在您主动操作时同步。',
        'type': 'optional',
      },
      {
        'category': '分析数据',
        'description': '匿名使用统计（如功能使用频率），用于改进产品体验。不包含个人信息或项目内容。',
        'type': 'optional',
      },
      {
        'category': '崩溃报告',
        'description': '应用崩溃时的错误日志，用于修复 Bug。不包含个人信息或项目内容。',
        'type': 'optional',
      },
      {
        'category': 'API 密钥',
        'description': 'AI 识别服务的 API 密钥存储在设备本地安全存储中，不会传输到我们的服务器。',
        'type': 'required',
      },
    ];
  }

  // ═══════════════════════════════════════════════════════════
  // 隐私政策
  // ═══════════════════════════════════════════════════════════

  /// 获取隐私政策全文（Markdown 格式）
  ///
  /// 用于在应用内展示隐私政策内容
  static String getPrivacyPolicyText() {
    return '''
# WriteFont 隐私政策

**生效日期：2024年1月1日**
**版本：v$currentPrivacyPolicyVersion**

## 1. 概述

WriteFont（手迹造字）是一款帮助用户创建手写字体的应用。我们非常重视您的隐私保护。本隐私政策说明我们如何收集、使用和保护您的信息。

## 2. 数据收集

### 2.1 本地数据
- **项目数据**：您创建的字体项目（手写字体、字符图片）存储在您的设备本地。
- **应用设置**：您的偏好设置存储在设备本地。

### 2.2 云同步数据（可选）
- 如果您选择启用云同步，项目数据将通过加密连接上传到 Supabase 云端。
- 云同步需要您创建账号并登录。
- 您可以随时删除云端数据。

### 2.3 分析数据（可选）
- 匿名使用统计数据，如功能使用频率。
- 不包含任何个人信息或项目内容。

### 2.4 崩溃报告（可选）
- 应用崩溃时的错误日志。
- 不包含个人信息或项目内容。

## 3. 数据使用

我们收集的数据仅用于：
- 提供核心功能（本地存储）
- 云同步服务（仅在您启用时）
- 改进产品体验（匿名统计）
- 修复应用问题（崩溃报告）

## 4. 数据存储与安全

- 本地数据使用设备安全存储机制保护。
- API 密钥存储在设备安全存储中（flutter_secure_storage）。
- 云同步数据通过 HTTPS 加密传输。
- 我们不会出售或与第三方共享您的数据。

## 5. 数据删除

- 您可以随时在应用内删除项目数据。
- 您可以随时关闭云同步并删除云端数据。
- 您可以随时在隐私设置中关闭分析和崩溃报告。

## 6. 第三方服务

- **Supabase**：用于云同步服务（可选）
- **SiliconFlow**：用于 AI 文字识别服务

## 7. 儿童隐私

本应用不面向 13 岁以下儿童，不会有意收集儿童的个人信息。

## 8. 隐私政策更新

我们可能会不时更新本隐私政策。更新后会在应用内通知您，并需要您重新确认。

## 9. 联系我们

如有隐私相关问题，请通过 GitHub Issues 联系我们：
https://github.com/nousresearch/writefont/issues
''';
  }

  /// 在外部浏览器中打开完整隐私政策
  static Future<void> openPrivacyPolicy() async {
    final uri = Uri.parse(privacyPolicyUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 数据导出（GDPR 数据可移植性）
  // ═══════════════════════════════════════════════════════════

  /// 导出所有隐私相关设置为 JSON
  ///
  /// 用于用户了解应用存储了哪些偏好数据
  static Future<Map<String, dynamic>> exportPrivacyData() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();

    // 只导出 privacy 相关的 key
    final privacyData = <String, dynamic>{};
    for (final key in keys) {
      if (key.startsWith('privacy_') || key.startsWith('cloud_')) {
        final value = prefs.get(key);
        // 不导出敏感 token
        if (key.contains('token') || key.contains('key')) {
          privacyData[key] = '***已隐藏***';
        } else {
          privacyData[key] = value;
        }
      }
    }

    return {
      'exportDate': DateTime.now().toIso8601String(),
      'privacySettings': privacyData,
      'dataCollectionDescription': getDataCollectionDescription(),
    };
  }

  /// 清除所有隐私相关数据（GDPR "被遗忘权"）
  ///
  /// 清除所有偏好设置中非必要的数据
  static Future<void> clearAllPrivacyData() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().toList();

    // 清除隐私和云相关设置
    for (final key in keys) {
      if (key.startsWith('privacy_') || key.startsWith('cloud_')) {
        await prefs.remove(key);
      }
    }

    // 重置缓存
    _cached = null;
  }
}
