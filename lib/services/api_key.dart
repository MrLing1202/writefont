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

  // ── 安全审计 ──
  static const String _securityAuditLogKey = 'security_audit_log';
  static const int _maxAuditEntries = 500;
  static final List<Map<String, dynamic>> _auditLog = [];

  // ── 安全检测 ──
  static const String _securityThreatsKey = 'security_threats';
  static const String _securityConfigKey = 'security_config';
  static int _failedAccessAttempts = 0;
  static DateTime? _lastFailedAttempt;
  static const int _maxFailedAttempts = 5;
  static const Duration _lockoutDuration = Duration(minutes: 15);
  static bool _isLockedOut = false;

  // ── 安全防护 ──
  static const String _ipBlocklistKey = 'security_ip_blocklist';
  static const String _rateLimitKey = 'security_rate_limit';
  static final Map<String, List<DateTime>> _rateLimitMap = {};
  static const int _maxRequestsPerMinute = 30;

  // ── 安全报告 ──
  static const String _securityReportKey = 'security_report';
  static DateTime? _lastReportTime;

  // ── 隐私设置 keys ──
  static const _keyAnalyticsEnabled = 'privacy_analytics_enabled';
  static const _keyCrashReportingEnabled = 'privacy_crash_reporting_enabled';
  static const _keyDataCollectionConsent = 'privacy_data_collection_consent';
  static const _keyPrivacyPolicyVersion = 'privacy_policy_version';

  /// 当前隐私政策版本号
  static const int currentPrivacyPolicyVersion = 1;

  /// 安全级别枚举
  static const int securityLevelLow = 0;
  static const int securityLevelMedium = 1;
  static const int securityLevelHigh = 2;
  static const int securityLevelCritical = 3;

  /// 隐私政策 URL
  static const String privacyPolicyUrl = 'https://writefont.app/privacy';

  /// 获取 SiliconFlow API Key
  static String get siliconFlowKey => _cached ?? '';

  // ═══════════════════════════════════════════════════════════
  // 安全审计功能
  // ═══════════════════════════════════════════════════════════

  /// 记录安全审计事件
  ///
  /// [eventType] 事件类型（如 'access', 'key_rotation', 'threat_detected'）
  /// [details] 事件详情
  /// [level] 安全级别（securityLevelLow ~ securityLevelCritical）
  static Future<void> logSecurityEvent(
    String eventType,
    String details, {
    int level = securityLevelLow,
  }) async {
    try {
      final entry = {
        'timestamp': DateTime.now().toIso8601String(),
        'eventType': eventType,
        'details': details,
        'level': level,
        'platform': 'flutter',
      };
      _auditLog.insert(0, entry);
      if (_auditLog.length > _maxAuditEntries) {
        _auditLog.removeRange(_maxAuditEntries, _auditLog.length);
      }
      await _persistAuditLog();
    } catch (e) {
      // 静默失败，审计日志不应影响主流程
    }
  }

  /// 持久化审计日志
  static Future<void> _persistAuditLog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_auditLog.take(_maxAuditEntries).toList());
      await prefs.setString(_securityAuditLogKey, json);
    } catch (_) {}
  }

  /// 加载审计日志
  static Future<void> _loadAuditLog() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_securityAuditLogKey);
      if (json != null) {
        final list = jsonDecode(json) as List;
        _auditLog.clear();
        _auditLog.addAll(list.cast<Map<String, dynamic>>());
      }
    } catch (_) {}
  }

  /// 获取审计日志列表
  static Future<List<Map<String, dynamic>>> getAuditLog({int limit = 50}) async {
    if (_auditLog.isEmpty) await _loadAuditLog();
    return List.unmodifiable(_auditLog.take(limit));
  }

  /// 按类型过滤审计日志
  static Future<List<Map<String, dynamic>>> getAuditLogByType(
    String eventType, {
    int limit = 50,
  }) async {
    if (_auditLog.isEmpty) await _loadAuditLog();
    return List.unmodifiable(
      _auditLog.where((e) => e['eventType'] == eventType).take(limit),
    );
  }

  /// 清除审计日志
  static Future<void> clearAuditLog() async {
    _auditLog.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_securityAuditLogKey);
    await logSecurityEvent('audit_cleared', '审计日志已清除', level: securityLevelMedium);
  }

  // ═══════════════════════════════════════════════════════════
  // 安全检测功能
  // ═══════════════════════════════════════════════════════════

  /// 检测当前安全状态
  ///
  /// 返回安全状态信息，包含威胁级别、锁定状态等
  static Future<Map<String, dynamic>> detectSecurityStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 检查锁定状态
      if (_isLockedOut) {
        if (_lastFailedAttempt != null) {
          final elapsed = DateTime.now().difference(_lastFailedAttempt!);
          if (elapsed > _lockoutDuration) {
            _isLockedOut = false;
            _failedAccessAttempts = 0;
          }
        }
      }

      // 检查密钥状态
      final keyExists = _cached != null || prefs.getString(_encryptionKeyPref) != null;

      // 检查隐私合规
      final consent = prefs.getBool(_keyDataCollectionConsent) ?? false;
      final policyAccepted = await isPrivacyPolicyAccepted();

      // 评估威胁级别
      int threatLevel = securityLevelLow;
      final threats = <String>[];

      if (_isLockedOut) {
        threatLevel = securityLevelCritical;
        threats.add('账户已锁定（多次失败访问尝试）');
      }
      if (_failedAccessAttempts >= _maxFailedAttempts - 1) {
        if (threatLevel < securityLevelHigh) threatLevel = securityLevelHigh;
        threats.add('接近失败访问上限（$_failedAccessAttempts/$_maxFailedAttempts）');
      }
      if (!keyExists) {
        if (threatLevel < securityLevelMedium) threatLevel = securityLevelMedium;
        threats.add('加密密钥未初始化');
      }
      if (!policyAccepted) {
        if (threatLevel < securityLevelLow) threatLevel = securityLevelLow;
        threats.add('隐私政策未确认');
      }

      return {
        'isLockedOut': _isLockedOut,
        'failedAttempts': _failedAccessAttempts,
        'maxFailedAttempts': _maxFailedAttempts,
        'threatLevel': threatLevel,
        'threats': threats,
        'keyExists': keyExists,
        'consentGiven': consent,
        'policyAccepted': policyAccepted,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'error': e.toString(),
        'threatLevel': securityLevelMedium,
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// 记录失败的访问尝试
  ///
  /// 达到上限后自动锁定账户
  static Future<void> recordFailedAccess(String reason) async {
    _failedAccessAttempts++;
    _lastFailedAttempt = DateTime.now();

    await logSecurityEvent(
      'access_failed',
      '失败访问尝试: $reason (第$_failedAccessAttempts次)',
      level: securityLevelMedium,
    );

    if (_failedAccessAttempts >= _maxFailedAttempts) {
      _isLockedOut = true;
      await logSecurityEvent(
        'account_locked',
        '账户已锁定（连续$_maxFailedAttempts次失败尝试）',
        level: securityLevelCritical,
      );
    }
  }

  /// 重置失败访问计数（成功访问后调用）
  static Future<void> resetFailedAccess() async {
    if (_failedAccessAttempts > 0) {
      await logSecurityEvent(
        'access_reset',
        '失败访问计数已重置（之前: $_failedAccessAttempts次）',
      );
    }
    _failedAccessAttempts = 0;
    _isLockedOut = false;
    _lastFailedAttempt = null;
  }

  /// 检查是否处于锁定状态
  static bool get isAccountLocked => _isLockedOut;

  /// 获取剩余锁定时间
  static Duration? get remainingLockoutTime {
    if (!_isLockedOut || _lastFailedAttempt == null) return null;
    final elapsed = DateTime.now().difference(_lastFailedAttempt!);
    final remaining = _lockoutDuration - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  // ═══════════════════════════════════════════════════════════
  // 安全防护功能
  // ═══════════════════════════════════════════════════════════

  /// 速率限制检查
  ///
  /// [identifier] 请求标识符（如用户ID、IP等）
  /// 返回 true 表示允许请求，false 表示已超限
  static bool checkRateLimit(String identifier) {
    final now = DateTime.now();
    final windowStart = now.subtract(const Duration(minutes: 1));

    // 清理过期记录
    final requests = _rateLimitMap[identifier] ?? [];
    requests.removeWhere((t) => t.isBefore(windowStart));

    if (requests.length >= _maxRequestsPerMinute) {
      logSecurityEvent(
        'rate_limit_exceeded',
        '速率限制触发: $identifier (${requests.length}次/分钟)',
        level: securityLevelMedium,
      );
      return false;
    }

    requests.add(now);
    _rateLimitMap[identifier] = requests;
    return true;
  }

  /// 输入安全消毒
  ///
  /// 防止注入攻击，移除潜在危险字符
  static String sanitizeInput(String input) {
    // 移除控制字符
    var sanitized = input.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    // 限制长度
    if (sanitized.length > 10000) {
      sanitized = sanitized.substring(0, 10000);
    }
    return sanitized;
  }

  /// 验证 API Key 格式
  ///
  /// 检查密钥格式是否合法，防止格式攻击
  static bool validateKeyFormat(String key) {
    // API Key 应为字母数字和连字符，长度在 20-200 之间
    final validPattern = RegExp(r'^[a-zA-Z0-9\-_]{20,200}$');
    return validPattern.hasMatch(key);
  }

  /// 获取安全配置
  static Future<Map<String, dynamic>> getSecurityConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_securityConfigKey);
      if (json != null) {
        return jsonDecode(json) as Map<String, dynamic>;
      }
    } catch (_) {}

    // 默认安全配置
    return {
      'maxFailedAttempts': _maxFailedAttempts,
      'lockoutDurationMinutes': _lockoutDuration.inMinutes,
      'rateLimitPerMinute': _maxRequestsPerMinute,
      'auditLogEnabled': true,
      'autoLockout': true,
    };
  }

  /// 更新安全配置
  static Future<void> updateSecurityConfig(Map<String, dynamic> config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_securityConfigKey, jsonEncode(config));
      await logSecurityEvent('config_updated', '安全配置已更新', level: securityLevelMedium);
    } catch (e) {
      await logSecurityEvent('config_update_failed', '安全配置更新失败: $e', level: securityLevelHigh);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 安全报告功能
  // ═══════════════════════════════════════════════════════════

  /// 生成安全报告
  ///
  /// 包含安全状态、威胁检测、审计摘要等信息
  static Future<Map<String, dynamic>> generateSecurityReport() async {
    try {
      if (_auditLog.isEmpty) await _loadAuditLog();
      final status = await detectSecurityStatus();

      // 统计各类型事件
      final eventCounts = <String, int>{};
      final levelCounts = <int, int>{};
      for (final entry in _auditLog) {
        final type = entry['eventType'] as String? ?? 'unknown';
        final level = entry['level'] as int? ?? securityLevelLow;
        eventCounts[type] = (eventCounts[type] ?? 0) + 1;
        levelCounts[level] = (levelCounts[level] ?? 0) + 1;
      }

      // 最近的高危事件
      final highRiskEvents = _auditLog
          .where((e) => (e['level'] as int? ?? 0) >= securityLevelHigh)
          .take(10)
          .toList();

      final report = {
        'reportTime': DateTime.now().toIso8601String(),
        'securityStatus': status,
        'auditSummary': {
          'totalEvents': _auditLog.length,
          'eventCounts': eventCounts,
          'levelCounts': levelCounts.map((k, v) => MapEntry(k.toString(), v)),
        },
        'highRiskEvents': highRiskEvents,
        'rateLimitStats': {
          'activeIdentifiers': _rateLimitMap.length,
          'totalTrackedRequests': _rateLimitMap.values.fold(0, (sum, list) => sum + list.length),
        },
        'recommendations': _generateSecurityRecommendations(status),
      };

      _lastReportTime = DateTime.now();
      return report;
    } catch (e) {
      return {
        'error': e.toString(),
        'reportTime': DateTime.now().toIso8601String(),
      };
    }
  }

  /// 生成安全建议
  static List<String> _generateSecurityRecommendations(Map<String, dynamic> status) {
    final recommendations = <String>[];

    if (status['isLockedOut'] == true) {
      recommendations.add('账户已锁定，请等待锁定解除或联系管理员');
    }
    if (status['threats'] != null && (status['threats'] as List).isNotEmpty) {
      recommendations.add('检测到安全威胁，请检查安全日志');
    }
    if (status['consentGiven'] != true) {
      recommendations.add('建议完成数据收集同意设置');
    }
    if (status['policyAccepted'] != true) {
      recommendations.add('请阅读并确认隐私政策');
    }
    if (_failedAccessAttempts > 0) {
      recommendations.add('存在失败访问记录（$_failedAccessAttempts次），建议检查访问来源');
    }
    if (recommendations.isEmpty) {
      recommendations.add('当前安全状态良好，无需额外操作');
    }

    return recommendations;
  }

  /// 获取安全报告文本（Markdown 格式）
  static Future<String> getSecurityReportText() async {
    final report = await generateSecurityReport();
    final status = report['securityStatus'] as Map<String, dynamic>? ?? {};
    final summary = report['auditSummary'] as Map<String, dynamic>? ?? {};
    final recommendations = report['recommendations'] as List<String>? ?? [];

    final buffer = StringBuffer();
    buffer.writeln('# WriteFont 安全报告');
    buffer.writeln();
    buffer.writeln('**生成时间**: ${report['reportTime']}');
    buffer.writeln();

    buffer.writeln('## 安全状态');
    final threatLevel = status['threatLevel'] as int? ?? 0;
    final threatLabels = ['低', '中', '高', '严重'];
    buffer.writeln('- **威胁级别**: ${threatLabels[threatLevel.clamp(0, 3)]}');
    buffer.writeln('- **账户锁定**: ${status['isLockedOut'] == true ? "是" : "否"}');
    buffer.writeln('- **失败尝试**: ${status['failedAttempts'] ?? 0}/${status['maxFailedAttempts'] ?? 5}');
    buffer.writeln('- **密钥状态**: ${status['keyExists'] == true ? "正常" : "未初始化"}');
    buffer.writeln();

    buffer.writeln('## 审计摘要');
    buffer.writeln('- **总事件数**: ${summary['totalEvents'] ?? 0}');
    final eventCounts = summary['eventCounts'] as Map<String, dynamic>? ?? {};
    for (final entry in eventCounts.entries) {
      buffer.writeln('  - ${entry.key}: ${entry.value}次');
    }
    buffer.writeln();

    buffer.writeln('## 安全建议');
    for (int i = 0; i < recommendations.length; i++) {
      buffer.writeln('${i + 1}. ${recommendations[i]}');
    }

    return buffer.toString();
  }

  static const String _encryptionKeyPref = 'storage_encryption_key';

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
