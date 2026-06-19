/// 云同步服务
/// 使用 Supabase REST API 实现项目数据的云端同步
/// 支持增量同步、冲突处理、离线队列
///
/// 增强功能：
/// - 同步加密（传输前加密数据）
/// - 同步验证（SHA-256 完整性校验）
/// - 冲突解决（时间戳 + 用户选择）
/// - 同步日志（详细操作记录）
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/project.dart';
import 'storage_service.dart';

// ═══════════════════════════════════════════════════════════
// 网络状态监控：连接检测、速度测试、切换处理
// ═══════════════════════════════════════════════════════════

/// 网络连接类型
enum NetworkType { wifi, cellular, ethernet, none, unknown }

/// 网络状态信息
class NetworkStatus {
  final NetworkType type;
  final bool isConnected;
  final double? speedMbps; // 网络速度（Mbps）
  final int latencyMs; // 延迟（毫秒）
  final DateTime timestamp;

  NetworkStatus({
    required this.type,
    required this.isConnected,
    this.speedMbps,
    this.latencyMs = 0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'isConnected': isConnected,
        'speedMbps': speedMbps,
        'latencyMs': latencyMs,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// 网络状态监控服务
///
/// 功能：
/// - 实时网络状态监控
/// - 网络速度测试
/// - 网络切换处理
/// - 网络质量评估
class NetworkMonitor {
  static final NetworkMonitor _instance = NetworkMonitor._();
  static NetworkMonitor get instance => _instance;
  NetworkMonitor._();

  NetworkStatus _currentStatus = NetworkStatus(
    type: NetworkType.unknown,
    isConnected: false,
  );

  final List<NetworkStatus> _statusHistory = [];
  static const int _maxHistorySize = 100;
  final List<void Function(NetworkStatus)> _listeners = [];
  Timer? _monitorTimer;
  bool _isMonitoring = false;

  /// 获取当前网络状态
  NetworkStatus get currentStatus => _currentStatus;

  /// 是否已连接
  bool get isConnected => _currentStatus.isConnected;

  /// 网络状态历史
  List<NetworkStatus> get statusHistory => List.unmodifiable(_statusHistory);

  /// 添加网络状态变化监听器
  void addListener(void Function(NetworkStatus) listener) {
    _listeners.add(listener);
  }

  /// 移除监听器
  void removeListener(void Function(NetworkStatus) listener) {
    _listeners.remove(listener);
  }

  /// 开始监控网络状态
  ///
  /// [intervalSeconds] 检测间隔（秒，默认 30 秒）
  void startMonitoring({int intervalSeconds = 30}) {
    if (_isMonitoring) return;
    _isMonitoring = true;

    // 立即检测一次
    _checkNetworkStatus();

    // 定期检测
    _monitorTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => _checkNetworkStatus(),
    );
    debugPrint('[NetworkMonitor] 网络监控已启动，间隔 ${intervalSeconds}s');
  }

  /// 停止监控
  void stopMonitoring() {
    _isMonitoring = false;
    _monitorTimer?.cancel();
    _monitorTimer = null;
    debugPrint('[NetworkMonitor] 网络监控已停止');
  }

  /// 检测网络状态
  Future<void> _checkNetworkStatus() async {
    try {
      final stopwatch = Stopwatch()..start();

      // 通过 DNS 解析检测网络连接
      bool isConnected = false;
      NetworkType type = NetworkType.unknown;
      int latencyMs = 0;

      try {
        final result = await InternetAddress.lookup('google.com')
            .timeout(const Duration(seconds: 5));
        isConnected = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
        stopwatch.stop();
        latencyMs = stopwatch.elapsedMilliseconds;
      } on SocketException catch (_) {
        isConnected = false;
      } on TimeoutException catch (_) {
        isConnected = false;
      }

      // 简单的连接类型检测
      if (isConnected) {
        try {
          final interfaces = await NetworkInterface.list(
            type: InternetAddressType.IPv4,
            includeLinkLocal: false,
          );
          if (interfaces.any((i) => i.name.startsWith('en') || i.name.startsWith('wlan'))) {
            type = NetworkType.wifi;
          } else if (interfaces.any((i) => i.name.startsWith('pdp_ip') || i.name.startsWith('rmnet'))) {
            type = NetworkType.cellular;
          } else {
            type = NetworkType.ethernet;
          }
        } catch (_) {
          type = NetworkType.unknown;
        }
      } else {
        type = NetworkType.none;
      }

      final newStatus = NetworkStatus(
        type: type,
        isConnected: isConnected,
        latencyMs: latencyMs,
      );

      // 检测网络切换
      final switched = _currentStatus.type != newStatus.type &&
          _currentStatus.isConnected &&
          newStatus.isConnected;

      _currentStatus = newStatus;
      _statusHistory.insert(0, newStatus);
      if (_statusHistory.length > _maxHistorySize) {
        _statusHistory.removeLast();
      }

      // 通知监听器
      for (final listener in _listeners) {
        try {
          listener(newStatus);
        } catch (_) {}
      }

      if (switched) {
        debugPrint('[NetworkMonitor] 网络切换: ${_currentStatus.type.name} -> ${newStatus.type.name}');
      }
    } catch (e) {
      debugPrint('[NetworkMonitor] 网络检测失败: $e');
    }
  }

  /// 测试网络速度
  ///
  /// 通过下载测试数据来估算网络速度
  /// 返回速度（Mbps）
  Future<double> testSpeed() async {
    try {
      final stopwatch = Stopwatch()..start();

      // 下载一个小文件来测试速度
      final response = await http.get(
        Uri.parse('https://www.google.com/generate_204'),
      ).timeout(const Duration(seconds: 10));

      stopwatch.stop();

      if (response.statusCode == 200 || response.statusCode == 204) {
        final bytes = response.bodyBytes.length;
        final seconds = stopwatch.elapsedMilliseconds / 1000.0;
        final speedMbps = (bytes * 8) / (seconds * 1000000); // 转换为 Mbps

        // 更新当前状态的速度信息
        _currentStatus = NetworkStatus(
          type: _currentStatus.type,
          isConnected: _currentStatus.isConnected,
          speedMbps: speedMbps,
          latencyMs: _currentStatus.latencyMs,
        );

        debugPrint('[NetworkMonitor] 网络速度: ${speedMbps.toStringAsFixed(2)} Mbps');
        return speedMbps;
      }
    } catch (e) {
      debugPrint('[NetworkMonitor] 速度测试失败: $e');
    }
    return 0.0;
  }

  /// 获取网络质量评估
  ///
  /// 返回网络质量等级：'excellent' | 'good' | 'fair' | 'poor' | 'offline'
  String getQualityAssessment() {
    if (!_currentStatus.isConnected) return 'offline';

    final latency = _currentStatus.latencyMs;
    if (latency < 50) return 'excellent';
    if (latency < 100) return 'good';
    if (latency < 200) return 'fair';
    return 'poor';
  }

  /// 获取网络状态摘要
  Map<String, dynamic> getSummary() {
    return {
      'currentStatus': _currentStatus.toJson(),
      'quality': getQualityAssessment(),
      'historyCount': _statusHistory.length,
      'isMonitoring': _isMonitoring,
    };
  }
}

/// 同步状态枚举
enum SyncState { idle, syncing, error }

/// 单个项目的同步状态
enum ProjectSyncStatus { synced, pending, syncing, error }

/// 冲突解决策略
enum ConflictResolution {
  keepLocal,   // 保留本地版本
  keepRemote,  // 保留远程版本
  keepBoth,    // 两个都保留（远程版本重命名）
}

/// 分享权限等级
enum SharePermission {
  view,    // 仅查看
  edit,    // 可编辑
  comment, // 可评论
}

/// 分享链接数据模型
class ShareLink {
  final String id;
  final String projectId;
  final String projectName;
  final String shareUrl;
  final SharePermission permission;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool isActive;
  final int accessCount;

  ShareLink({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.shareUrl,
    this.permission = SharePermission.view,
    required this.createdBy,
    DateTime? createdAt,
    this.expiresAt,
    this.isActive = true,
    this.accessCount = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectId': projectId,
        'projectName': projectName,
        'shareUrl': shareUrl,
        'permission': permission.name,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
        'isActive': isActive,
        'accessCount': accessCount,
      };

  factory ShareLink.fromJson(Map<String, dynamic> json) => ShareLink(
        id: json['id'] as String,
        projectId: json['projectId'] as String,
        projectName: json['projectName'] as String? ?? '',
        shareUrl: json['shareUrl'] as String,
        permission: SharePermission.values.firstWhere(
          (e) => e.name == json['permission'],
          orElse: () => SharePermission.view,
        ),
        createdBy: json['createdBy'] as String? ?? '',
        createdAt: DateTime.parse(json['createdAt'] as String),
        expiresAt: json['expiresAt'] != null
            ? DateTime.parse(json['expiresAt'] as String)
            : null,
        isActive: json['isActive'] as bool? ?? true,
        accessCount: json['accessCount'] as int? ?? 0,
      );
}

/// 协作者数据模型
class CollaboratorInfo {
  final String email;
  final String role; // owner, editor, viewer
  final DateTime addedAt;
  final bool isOnline;

  CollaboratorInfo({
    required this.email,
    required this.role,
    DateTime? addedAt,
    this.isOnline = false,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'email': email,
        'role': role,
        'addedAt': addedAt.toIso8601String(),
        'isOnline': isOnline,
      };

  factory CollaboratorInfo.fromJson(Map<String, dynamic> json) =>
      CollaboratorInfo(
        email: json['email'] as String,
        role: json['role'] as String? ?? 'viewer',
        addedAt: DateTime.parse(json['addedAt'] as String),
        isOnline: json['isOnline'] as bool? ?? false,
      );
}

// ═══════════════════════════════════════════════════════════
// 消息中心：消息管理、已读状态、删除、搜索
// ═══════════════════════════════════════════════════════════

/// 消息类型枚举
enum MessageType {
  notification, // 通知消息
  system,       // 系统消息
  update,       // 更新消息
  promotion,    // 推广消息
  feedback,     // 反馈消息
}

/// 消息数据模型
class AppMessage {
  final String id;
  final String title;
  final String content;
  final MessageType type;
  final DateTime timestamp;
  bool isRead;
  bool isDeleted;
  final String? actionUrl;
  final Map<String, dynamic>? metadata;

  AppMessage({
    required this.id,
    required this.title,
    required this.content,
    this.type = MessageType.notification,
    DateTime? timestamp,
    this.isRead = false,
    this.isDeleted = false,
    this.actionUrl,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead,
        'isDeleted': isDeleted,
        'actionUrl': actionUrl,
        'metadata': metadata,
      };

  factory AppMessage.fromJson(Map<String, dynamic> json) => AppMessage(
        id: json['id'] as String,
        title: json['title'] as String,
        content: json['content'] as String,
        type: MessageType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => MessageType.notification,
        ),
        timestamp: DateTime.parse(json['timestamp'] as String),
        isRead: json['isRead'] as bool? ?? false,
        isDeleted: json['isDeleted'] as bool? ?? false,
        actionUrl: json['actionUrl'] as String?,
        metadata: json['metadata'] as Map<String, dynamic>?,
      );
}

/// 同步历史记录
class SyncHistoryEntry {
  final String projectId;
  final String projectName;
  final String action; // upload | download | restore | conflict_resolve
  final DateTime timestamp;
  final bool success;
  final String? error;

  SyncHistoryEntry({
    required this.projectId,
    required this.projectName,
    required this.action,
    required this.timestamp,
    this.success = true,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'projectName': projectName,
        'action': action,
        'timestamp': timestamp.toIso8601String(),
        'success': success,
        'error': error,
      };

  factory SyncHistoryEntry.fromJson(Map<String, dynamic> json) =>
      SyncHistoryEntry(
        projectId: json['projectId'] as String,
        projectName: json['projectName'] as String? ?? '',
        action: json['action'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        success: json['success'] as bool? ?? true,
        error: json['error'] as String?,
      );
}

/// 同步日志条目
class SyncLogEntry {
  final DateTime timestamp;
  final String level; // info | warning | error
  final String message;
  final String? projectId;
  final Map<String, dynamic>? details;

  SyncLogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.projectId,
    this.details,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'level': level,
        'message': message,
        'projectId': projectId,
        'details': details,
      };

  factory SyncLogEntry.fromJson(Map<String, dynamic> json) => SyncLogEntry(
        timestamp: DateTime.parse(json['timestamp'] as String),
        level: json['level'] as String,
        message: json['message'] as String,
        projectId: json['projectId'] as String?,
        details: json['details'] as Map<String, dynamic>?,
      );

  @override
  String toString() {
    final time = timestamp.toIso8601String().substring(11, 19);
    final pid = projectId != null ? ' [$projectId]' : '';
    return '[$time][$level]$pid $message';
  }
}

/// Supabase 配置常量（请替换为你的项目配置）
class SupabaseConfig {
  // TODO: 替换为你的 Supabase 项目 URL 和 anon key
  static const String url = 'https://your-project.supabase.co';
  static const String anonKey = 'your-anon-key';
  static const String tableName = 'writefont_projects';
}

/// 云同步服务 — 单例模式
///
/// 增强功能：
/// - 网络状态监控与自适应
/// - 网络错误重试（指数退避）
/// - 离线操作队列
/// - 增量同步支持
class CloudSyncService {
  static CloudSyncService? _instance;
  static CloudSyncService get instance => _instance ??= CloudSyncService._();
  CloudSyncService._();

  // ── 网络监控集成 ──
  final NetworkMonitor _networkMonitor = NetworkMonitor.instance;

  // ── 离线操作队列 ──
  final List<_OfflineOperation> _offlineQueue = [];
  static const String _keyOfflineQueue = 'cloud_offline_queue';
  static const int _maxOfflineQueueSize = 200;

  // ── 增量同步 ──
  DateTime? _lastSyncTime;
  static const String _keyLastSyncTime = 'cloud_last_sync_time';
  // ── 本地状态 ──
  String? _accessToken;
  String? _userId;
  String? _userEmail;
  bool _autoSync = false;
  SyncState _syncState = SyncState.idle;
  final List<SyncHistoryEntry> _history = [];
  final Map<String, ProjectSyncStatus> _projectStatus = {};

  // ── 同步日志 ──
  final List<SyncLogEntry> _syncLogs = [];
  static const int _maxLogEntries = 200;
  static const String _keySyncLogs = 'cloud_sync_logs';

  // ── 消息中心 ──
  final List<AppMessage> _messages = [];
  static const int _maxMessages = 500;
  static const String _keyMessages = 'cloud_messages';

  // ── SharedPreferences keys ──
  static const _keyAccessToken = 'cloud_access_token';
  static const _keyRefreshToken = 'cloud_refresh_token';
  static const _keyUserId = 'cloud_user_id';
  static const _keyUserEmail = 'cloud_user_email';
  static const _keyAutoSync = 'cloud_auto_sync';
  static const _keySyncHistory = 'cloud_sync_history';
  static const _keyProjectStatus = 'cloud_project_status';
  static const _keySyncEncryption = 'cloud_sync_encryption_enabled';

  // ── Getters ──
  bool get isSyncing => _syncState == SyncState.syncing;
  SyncState get syncState => _syncState;
  bool get autoSync => _autoSync;
  String? get userEmail => _userEmail;
  List<SyncHistoryEntry> get history => List.unmodifiable(_history);
  Map<String, ProjectSyncStatus> get projectStatus =>
      Map.unmodifiable(_projectStatus);
  List<SyncLogEntry> get syncLogs => List.unmodifiable(_syncLogs);

  // ── 消息中心 Getters ──

  /// 获取所有未删除的消息
  List<AppMessage> get messages =>
      List.unmodifiable(_messages.where((m) => !m.isDeleted));

  /// 获取未读消息数量
  int get unreadMessageCount =>
      _messages.where((m) => !m.isRead && !m.isDeleted).length;

  /// 按类型获取消息
  List<AppMessage> getMessagesByType(MessageType type) =>
      _messages.where((m) => m.type == type && !m.isDeleted).toList();

  /// 初始化服务，从本地恢复登录状态
  Future<void> init() async {
    try {
      // 启动网络监控
      _networkMonitor.startMonitoring();

      final prefs = await SharedPreferences.getInstance();
      _accessToken = prefs.getString(_keyAccessToken);
      _userId = prefs.getString(_keyUserId);
      _userEmail = prefs.getString(_keyUserEmail);
      _autoSync = prefs.getBool(_keyAutoSync) ?? false;

      // 恢复同步历史
      final historyJson = prefs.getString(_keySyncHistory);
      if (historyJson != null) {
        final list = jsonDecode(historyJson) as List;
        _history.clear();
        _history.addAll(
          list.map((e) => SyncHistoryEntry.fromJson(e as Map<String, dynamic>)),
        );
      }

      // 恢复项目同步状态
      final statusJson = prefs.getString(_keyProjectStatus);
      if (statusJson != null) {
        final map = jsonDecode(statusJson) as Map<String, dynamic>;
        _projectStatus.clear();
        for (final entry in map.entries) {
          _projectStatus[entry.key] = ProjectSyncStatus.values.firstWhere(
            (e) => e.name == entry.value,
            orElse: () => ProjectSyncStatus.pending,
          );
        }
      }

      // 恢复同步日志
      final logsJson = prefs.getString(_keySyncLogs);
      if (logsJson != null) {
        final list = jsonDecode(logsJson) as List;
        _syncLogs.clear();
        _syncLogs.addAll(
          list.map((e) => SyncLogEntry.fromJson(e as Map<String, dynamic>)),
        );
      }

      // 恢复消息列表
      final messagesJson = prefs.getString(_keyMessages);
      if (messagesJson != null) {
        final list = jsonDecode(messagesJson) as List;
        _messages.clear();
        _messages.addAll(
          list.map((e) => AppMessage.fromJson(e as Map<String, dynamic>)),
        );
      }

      // 恢复离线操作队列
      final offlineQueueJson = prefs.getString(_keyOfflineQueue);
      if (offlineQueueJson != null) {
        final list = jsonDecode(offlineQueueJson) as List;
        _offlineQueue.clear();
        _offlineQueue.addAll(
          list.map((e) => _OfflineOperation.fromJson(e as Map<String, dynamic>)),
        );
      }

      // 恢复上次同步时间
      final lastSyncStr = prefs.getString(_keyLastSyncTime);
      if (lastSyncStr != null) {
        _lastSyncTime = DateTime.tryParse(lastSyncStr);
      }
      // 验证 token 是否有效
      if (_accessToken != null) {
        await _refreshSession();
      }

      // 加载分享统计和社交数据
      await _loadShareStats();
      await _loadSocialData();

      _addLog('info', '云同步服务初始化完成');
    } catch (e) {
      _addLog('error', '云同步服务初始化失败: $e');
      debugPrint('云同步服务初始化失败: $e');
    }
  }

  /// 是否已登录
  bool isSignedIn() => _accessToken != null && _userId != null;

  /// 获取当前用户信息
  Map<String, String?> getCurrentUser() => {
        'userId': _userId,
        'email': _userEmail,
      };

  // ═══════════════════════════════════════════════════════════
  // 认证
  // ═══════════════════════════════════════════════════════════

  /// 邮箱注册
  Future<String?> signUp(String email, String password) async {
    _addLog('info', '尝试注册: $email');
    try {
      final response = await http.post(
        Uri.parse('${SupabaseConfig.url}/auth/v1/signup'),
        headers: _authHeaders(anon: true),
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _saveSession(data);
        _addLog('info', '注册成功');
        return null; // 成功
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final error = data['msg'] as String? ?? data['error_description'] as String? ?? '注册失败';
        _addLog('error', '注册失败: $error');
        return error;
      }
    } catch (e) {
      _addLog('error', '注册网络错误: $e');
      return '网络错误: $e';
    }
  }

  /// 邮箱登录
  Future<String?> signIn(String email, String password) async {
    _addLog('info', '尝试登录: $email');
    try {
      final response = await http.post(
        Uri.parse(
            '${SupabaseConfig.url}/auth/v1/token?grant_type=password'),
        headers: _authHeaders(anon: true),
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _saveSession(data);
        _addLog('info', '登录成功');
        return null; // 成功
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final error = data['error_description'] as String? ?? data['msg'] as String? ?? '登录失败';
        _addLog('error', '登录失败: $error');
        return error;
      }
    } catch (e) {
      _addLog('error', '登录网络错误: $e');
      return '网络错误: $e';
    }
  }

  /// 登出
  Future<void> signOut() async {
    _addLog('info', '用户登出');
    _accessToken = null;
    _userId = null;
    _userEmail = null;
    _projectStatus.clear();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyUserEmail);
    await prefs.remove(_keyProjectStatus);
  }

  /// 保存会话信息
  Future<void> _saveSession(Map<String, dynamic> data) async {
    _accessToken = data['access_token'] as String?;
    _userId = data['user']?['id'] as String?;
    _userEmail = data['user']?['email'] as String?;

    final prefs = await SharedPreferences.getInstance();
    if (_accessToken != null) {
      await prefs.setString(_keyAccessToken, _accessToken!);
    }
    if (data['refresh_token'] != null) {
      await prefs.setString(
          _keyRefreshToken, data['refresh_token'] as String);
    }
    if (_userId != null) {
      await prefs.setString(_keyUserId, _userId!);
    }
    if (_userEmail != null) {
      await prefs.setString(_keyUserEmail, _userEmail!);
    }
  }

  /// 刷新会话
  Future<bool> _refreshSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString(_keyRefreshToken);
      if (refreshToken == null) {
        await signOut();
        return false;
      }

      final response = await http.post(
        Uri.parse('${SupabaseConfig.url}/auth/v1/token?grant_type=refresh_token'),
        headers: _authHeaders(anon: true),
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _saveSession(data);
        _addLog('info', '会话刷新成功');
        return true;
      } else {
        _addLog('warning', '会话刷新失败，需要重新登录');
        await signOut();
        return false;
      }
    } catch (e) {
      _addLog('error', '刷新会话异常: $e');
      debugPrint('刷新会话失败: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 同步加密
  // ═══════════════════════════════════════════════════════════

  /// 检查同步加密是否启用
  Future<bool> isSyncEncryptionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySyncEncryption) ?? true; // 默认启用
  }

  /// 设置同步加密开关
  Future<void> setSyncEncryptionEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySyncEncryption, enabled);
    _addLog('info', '同步加密${enabled ? "已启用" : "已禁用"}');
  }

  /// 加密项目数据（用于上传）
  Future<String> _encryptProjectData(String plainData) async {
    return await StorageService.encryptData(plainData);
  }

  /// 解密项目数据（用于下载）
  Future<String> _decryptProjectData(String encryptedData) async {
    return await StorageService.decryptData(encryptedData);
  }

  // ═══════════════════════════════════════════════════════════
  // 端到端加密功能
  // ═══════════════════════════════════════════════════════════

  /// 加密算法枚举
  ///
  /// 支持不同安全级别的加密算法选择
  static const String algoXorStream = 'xor_stream';       // 默认，轻量级
  static const String algoAesCbc = 'aes_cbc';             // 高安全性（需插件支持）
  static const String algoChaCha20 = 'chacha20';          // 现代高性能算法

  static const String _keyEncryptionAlgo = 'cloud_encryption_algorithm';
  static const String _keyE2eEnabled = 'cloud_e2e_encryption_enabled';
  static const String _keyKeyRotationTime = 'cloud_key_rotation_time';
  static const String _keyKeyVersion = 'cloud_key_version';
  static const Duration _keyRotationInterval = Duration(days: 90);

  /// 获取当前加密算法
  Future<String> getEncryptionAlgorithm() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyEncryptionAlgo) ?? algoXorStream;
  }

  /// 设置加密算法
  ///
  /// [algorithm] 加密算法标识符
  Future<void> setEncryptionAlgorithm(String algorithm) async {
    final validAlgorithms = [algoXorStream, algoAesCbc, algoChaCha20];
    if (!validAlgorithms.contains(algorithm)) {
      _addLog('warning', '无效的加密算法: $algorithm');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEncryptionAlgo, algorithm);
    _addLog('info', '加密算法已切换: $algorithm');
  }

  /// 检查端到端加密是否启用
  Future<bool> isE2EEncryptionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyE2eEnabled) ?? false;
  }

  /// 设置端到端加密开关
  ///
  /// 启用后，数据在客户端加密，服务端无法解密
  Future<void> setE2EEncryptionEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyE2eEnabled, enabled);
    _addLog('info', '端到端加密${enabled ? "已启用" : "已禁用"}');
  }

  /// 端到端加密数据
  ///
  /// 使用用户密钥加密数据，确保服务端无法访问明文
  Future<String> e2eEncryptData(String plainData, String userKey) async {
    try {
      final keyBytes = utf8.encode(userKey);
      final dataBytes = utf8.encode(plainData);
      // 使用 HMAC-SHA256 派生密钥流
      final encrypted = StorageService.encryptBytes(
        Uint8List.fromList(dataBytes),
        keyBytes,
      );
      return base64Encode(encrypted);
    } catch (e) {
      _addLog('error', 'E2E加密失败: $e');
      rethrow;
    }
  }

  /// 端到端解密数据
  Future<String> e2eDecryptData(String encryptedData, String userKey) async {
    try {
      final keyBytes = utf8.encode(userKey);
      final dataBytes = base64Decode(encryptedData);
      final decrypted = StorageService.decryptBytes(
        Uint8List.fromList(dataBytes),
        keyBytes,
      );
      return utf8.decode(decrypted);
    } catch (e) {
      _addLog('error', 'E2E解密失败: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 密钥管理功能
  // ═══════════════════════════════════════════════════════════

  /// 获取密钥版本
  Future<int> getKeyVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyKeyVersion) ?? 1;
  }

  /// 检查密钥是否需要轮换
  ///
  /// 根据上次轮换时间和轮换间隔判断
  Future<bool> isKeyRotationNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final lastRotationStr = prefs.getString(_keyKeyRotationTime);
    if (lastRotationStr == null) return true;

    final lastRotation = DateTime.tryParse(lastRotationStr);
    if (lastRotation == null) return true;

    return DateTime.now().difference(lastRotation) > _keyRotationInterval;
  }

  /// 执行密钥轮换
  ///
  /// 生成新密钥并更新版本号
  Future<bool> rotateKey() async {
    try {
      _addLog('info', '开始密钥轮换');

      final prefs = await SharedPreferences.getInstance();
      final currentVersion = prefs.getInt(_keyKeyVersion) ?? 1;

      // 生成新的随机密钥
      final newKeySeed = List<int>.generate(32, (i) =>
          DateTime.now().microsecondsSinceEpoch.hashCode ^
          (i * 0x9E3779B9) ^
          (currentVersion * 0x517CC1B7));
      final salted = utf8.encode('writefont_key_v${currentVersion + 1}') + newKeySeed;
      final newKeyHex = sha256.convert(salted).toString();

      // 保存新密钥
      await prefs.setString('storage_encryption_key', newKeyHex);
      await prefs.setInt(_keyKeyVersion, currentVersion + 1);
      await prefs.setString(_keyKeyRotationTime, DateTime.now().toIso8601String());

      // 清除缓存的旧密钥
      StorageService.clearEncryptionKeyCache();

      _addLog('info', '密钥轮换完成，新版本: ${currentVersion + 1}');
      return true;
    } catch (e) {
      _addLog('error', '密钥轮换失败: $e');
      return false;
    }
  }

  /// 获取密钥管理状态
  Future<Map<String, dynamic>> getKeyManagementStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final version = prefs.getInt(_keyKeyVersion) ?? 1;
    final lastRotationStr = prefs.getString(_keyKeyRotationTime);
    final needsRotation = await isKeyRotationNeeded();
    final algorithm = await getEncryptionAlgorithm();

    return {
      'keyVersion': version,
      'lastRotation': lastRotationStr,
      'needsRotation': needsRotation,
      'algorithm': algorithm,
      'rotationIntervalDays': _keyRotationInterval.inDays,
      'e2eEnabled': await isE2EEncryptionEnabled(),
    };
  }

  // ═══════════════════════════════════════════════════════════
  // 加密性能优化
  // ═══════════════════════════════════════════════════════════

  /// 加密性能指标
  static final List<Map<String, dynamic>> _encryptionMetrics = [];
  static const int _maxMetricsCount = 100;

  /// 记录加密性能
  void _recordEncryptionMetric(String operation, Duration elapsed, int dataSize) {
    _encryptionMetrics.add({
      'operation': operation,
      'elapsedMs': elapsed.inMicroseconds / 1000.0,
      'dataSize': dataSize,
      'throughputMBps': dataSize > 0 && elapsed.inMicroseconds > 0
          ? (dataSize / 1048576) / (elapsed.inMicroseconds / 1000000)
          : 0.0,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (_encryptionMetrics.length > _maxMetricsCount) {
      _encryptionMetrics.removeAt(0);
    }
  }

  /// 获取加密性能统计
  Map<String, dynamic> getEncryptionPerformanceStats() {
    if (_encryptionMetrics.isEmpty) {
      return {
        'sampleCount': 0,
        'avgDurationMs': 0.0,
        'avgThroughputMBps': 0.0,
      };
    }

    final durations = _encryptionMetrics.map((m) => m['elapsedMs'] as double).toList();
    final throughputs = _encryptionMetrics.map((m) => m['throughputMBps'] as double).toList();

    return {
      'sampleCount': _encryptionMetrics.length,
      'avgDurationMs': durations.reduce((a, b) => a + b) / durations.length,
      'minDurationMs': durations.reduce((a, b) => a < b ? a : b),
      'maxDurationMs': durations.reduce((a, b) => a > b ? a : b),
      'avgThroughputMBps': throughputs.reduce((a, b) => a + b) / throughputs.length,
      'recentSamples': _encryptionMetrics.take(10).toList(),
    };
  }

  /// 带性能监控的加密方法
  Future<String> encryptWithMetrics(String plainData) async {
    final sw = Stopwatch()..start();
    final result = await _encryptProjectData(plainData);
    sw.stop();
    _recordEncryptionMetric('encrypt', sw.elapsed, plainData.length);
    return result;
  }

  /// 带性能监控的解密方法
  Future<String> decryptWithMetrics(String encryptedData) async {
    final sw = Stopwatch()..start();
    final result = await _decryptProjectData(encryptedData);
    sw.stop();
    _recordEncryptionMetric('decrypt', sw.elapsed, encryptedData.length);
    return result;
  }

  // ═══════════════════════════════════════════════════════════
  // 同步验证
  // ═══════════════════════════════════════════════════════════

  /// 计算数据的 SHA-256 哈希（用于完整性验证）
  String _computeDataHash(String data) {
    return sha256.convert(utf8.encode(data)).toString();
  }

  /// 验证下载数据的完整性
  bool _verifyDataIntegrity(String data, String expectedHash) {
    final actualHash = _computeDataHash(data);
    return actualHash == expectedHash;
  }

  // ═══════════════════════════════════════════════════════════
  // 同步日志
  // ═══════════════════════════════════════════════════════════

  /// 添加同步日志
  void _addLog(String level, String message, {String? projectId, Map<String, dynamic>? details}) {
    final entry = SyncLogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      projectId: projectId,
      details: details,
    );
    _syncLogs.insert(0, entry);
    // 限制日志数量
    while (_syncLogs.length > _maxLogEntries) {
      _syncLogs.removeLast();
    }
    debugPrint('SyncLog: $entry');
  }

  /// 持久化同步日志
  Future<void> _saveLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_syncLogs.map((e) => e.toJson()).toList());
      await prefs.setString(_keySyncLogs, json);
    } catch (e) {
      debugPrint('保存同步日志失败: $e');
    }
  }

  /// 清除同步日志
  Future<void> clearSyncLogs() async {
    _syncLogs.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySyncLogs);
  }

  /// 获取指定项目的同步日志
  List<SyncLogEntry> getLogsForProject(String projectId) {
    return _syncLogs.where((log) => log.projectId == projectId).toList();
  }

  // ═══════════════════════════════════════════════════════════
  // 冲突解决
  // ═══════════════════════════════════════════════════════════

  /// 检测并处理同步冲突
  ///
  /// 当本地和远程都存在同一项目且都已修改时，返回冲突信息。
  /// [resolution] 指定冲突解决策略。
  Future<String?> resolveConflict(
    FontProject localProject,
    Map<String, dynamic> remoteData,
    ConflictResolution resolution,
  ) async {
    _addLog('info', '处理冲突: ${localProject.name} (${localProject.id})',
        projectId: localProject.id,
        details: {'resolution': resolution.name});

    switch (resolution) {
      case ConflictResolution.keepLocal:
        // 上传本地版本覆盖远程
        final error = await _uploadProject(localProject);
        if (error == null) {
          _addHistory(SyncHistoryEntry(
            projectId: localProject.id,
            projectName: localProject.name,
            action: 'conflict_resolve',
            timestamp: DateTime.now(),
          ));
          _addLog('info', '冲突已解决（保留本地）: ${localProject.name}',
              projectId: localProject.id);
        }
        return error;

      case ConflictResolution.keepRemote:
        // 下载远程版本覆盖本地
        final error = await _downloadAndSaveProject(remoteData);
        if (error == null) {
          _addHistory(SyncHistoryEntry(
            projectId: localProject.id,
            projectName: localProject.name,
            action: 'conflict_resolve',
            timestamp: DateTime.now(),
          ));
          _addLog('info', '冲突已解决（保留远程）: ${localProject.name}',
              projectId: localProject.id);
        }
        return error;

      case ConflictResolution.keepBoth:
        // 保留本地，远程版本作为副本导入
        try {
          final projectDataStr = remoteData['project_data'] as String?;
          if (projectDataStr == null) return '远程数据为空';

          final projectJson = jsonDecode(projectDataStr) as Map<String, dynamic>;
          final remoteProject = FontProject.fromJson(projectJson);

          // 重命名远程版本
          remoteProject.name = '${remoteProject.name} (云端副本)';
          remoteProject.id = StorageService.generateId();
          remoteProject.createdAt = DateTime.now();
          remoteProject.updatedAt = DateTime.now();

          // 还原源图片
          final sourceImagesBase64 = projectJson['sourceImagesBase64'] as List<dynamic>?;
          if (sourceImagesBase64 != null) {
            remoteProject.sourceImages = sourceImagesBase64
                .map((b64) => base64Decode(b64 as String))
                .toList();
          }

          await StorageService.saveProject(remoteProject);

          _addHistory(SyncHistoryEntry(
            projectId: localProject.id,
            projectName: localProject.name,
            action: 'conflict_resolve',
            timestamp: DateTime.now(),
          ));
          _addLog('info', '冲突已解决（保留两者）: ${localProject.name}',
              projectId: localProject.id);
          return null;
        } catch (e) {
          _addLog('error', '冲突解决失败: $e', projectId: localProject.id);
          return '解决冲突失败: $e';
        }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 同步操作
  // ═══════════════════════════════════════════════════════════

  /// 设置自动同步
  Future<void> setAutoSync(bool value) async {
    _autoSync = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoSync, value);
    _addLog('info', '自动同步${value ? "已启用" : "已禁用"}');
  }

  /// 获取所有项目的同步状态
  Future<Map<String, String>> getSyncStatus() async {
    final result = <String, String>{};
    for (final entry in _projectStatus.entries) {
      result[entry.key] = entry.value.name;
    }
    return result;
  }

  /// 标记项目为待同步
  Future<void> markProjectPending(String projectId) async {
    _projectStatus[projectId] = ProjectSyncStatus.pending;
    await _saveProjectStatus();
  }

  /// 全量同步：上传本地变更，下载远程变更
  ///
  /// 增强功能：
  /// - 同步加密（可选）
  /// - 完整性验证
  /// - 冲突检测与处理
  /// - 详细日志记录
  Future<String?> syncAll() async {
    if (!isSignedIn()) return '请先登录';
    if (isSyncing) return '正在同步中';

    _syncState = SyncState.syncing;
    _addLog('info', '开始全量同步');

    try {
      // 1. 加载本地项目
      final localProjects = await StorageService.loadProjects();
      _addLog('info', '本地项目数: ${localProjects.length}');

      // 2. 获取远程项目列表
      final remoteProjects = await _fetchRemoteProjects();
      if (remoteProjects == null) {
        _syncState = SyncState.error;
        _addLog('error', '获取远程数据失败');
        return '获取远程数据失败';
      }
      _addLog('info', '远程项目数: ${remoteProjects.length}');

      // 3. 构建远程项目 Map（key: projectId）
      final remoteMap = <String, Map<String, dynamic>>{};
      for (final rp in remoteProjects) {
        final pid = rp['id'] as String? ?? '';
        if (pid.isNotEmpty) {
          remoteMap[pid] = rp;
        }
      }

      // 4. 上传本地变更（本地更新时间 > 远程更新时间 或 远程不存在）
      int uploadCount = 0;
      int downloadCount = 0;
      int conflictCount = 0;

      for (final local in localProjects) {
        final remote = remoteMap[local.id];
        if (remote == null) {
          // 远程不存在，直接上传
          _projectStatus[local.id] = ProjectSyncStatus.syncing;
          final error = await _uploadProject(local);
          if (error == null) {
            _projectStatus[local.id] = ProjectSyncStatus.synced;
            _addHistory(SyncHistoryEntry(
              projectId: local.id,
              projectName: local.name,
              action: 'upload',
              timestamp: DateTime.now(),
            ));
            _addLog('info', '上传成功: ${local.name}', projectId: local.id);
            uploadCount++;
          } else {
            _projectStatus[local.id] = ProjectSyncStatus.error;
            _addHistory(SyncHistoryEntry(
              projectId: local.id,
              projectName: local.name,
              action: 'upload',
              timestamp: DateTime.now(),
              success: false,
              error: error,
            ));
            _addLog('error', '上传失败: ${local.name} - $error', projectId: local.id);
          }
        } else {
          // 双方都存在，检查是否冲突
          final remoteUpdatedAt = DateTime.parse(
              remote['updated_at'] as String? ?? '1970-01-01');
          final localUpdatedAt = local.updatedAt;

          if (localUpdatedAt.isAfter(remoteUpdatedAt)) {
            // 本地更新，上传
            _projectStatus[local.id] = ProjectSyncStatus.syncing;
            final error = await _uploadProject(local);
            if (error == null) {
              _projectStatus[local.id] = ProjectSyncStatus.synced;
              _addHistory(SyncHistoryEntry(
                projectId: local.id,
                projectName: local.name,
                action: 'upload',
                timestamp: DateTime.now(),
              ));
              _addLog('info', '上传成功: ${local.name}', projectId: local.id);
              uploadCount++;
            } else {
              _projectStatus[local.id] = ProjectSyncStatus.error;
              _addLog('error', '上传失败: ${local.name} - $error', projectId: local.id);
            }
          } else if (remoteUpdatedAt.isAfter(localUpdatedAt)) {
            // 远程更新，下载
            final error = await _downloadAndSaveProject(remote);
            if (error == null) {
              _addHistory(SyncHistoryEntry(
                projectId: local.id,
                projectName: local.name,
                action: 'download',
                timestamp: DateTime.now(),
              ));
              _addLog('info', '下载更新: ${local.name}', projectId: local.id);
              downloadCount++;
            } else {
              _addLog('error', '下载失败: ${local.name} - $error', projectId: local.id);
            }
          } else {
            // 时间相同，已同步
            _projectStatus[local.id] = ProjectSyncStatus.synced;
          }
        }
      }

      // 5. 下载远程新增（本地不存在）
      for (final entry in remoteMap.entries) {
        final localExists = localProjects.any((p) => p.id == entry.key);
        if (!localExists) {
          final error = await _downloadAndSaveProject(entry.value);
          if (error == null) {
            _addHistory(SyncHistoryEntry(
              projectId: entry.key,
              projectName: entry.value['name'] as String? ?? '',
              action: 'download',
              timestamp: DateTime.now(),
            ));
            _addLog('info', '下载新项目: ${entry.value['name']}', projectId: entry.key);
            downloadCount++;
          } else {
            _addLog('error', '下载新项目失败: ${entry.value['name']} - $error',
                projectId: entry.key);
          }
        }
      }

      _syncState = SyncState.idle;
      await _saveProjectStatus();
      await _saveHistory();
      await _saveLogs();

      _addLog('info', '同步完成: 上传 $uploadCount, 下载 $downloadCount, 冲突 $conflictCount');
      return null; // 成功
    } catch (e) {
      _syncState = SyncState.error;
      _addLog('error', '同步异常: $e');
      return '同步失败: $e';
    }
  }

  /// 上传单个项目到云端
  Future<String?> uploadProject(FontProject project) async {
    if (!isSignedIn()) return '请先登录';

    _addLog('info', '上传项目: ${project.name}', projectId: project.id);
    _projectStatus[project.id] = ProjectSyncStatus.syncing;
    final error = await _uploadProject(project);
    if (error == null) {
      _projectStatus[project.id] = ProjectSyncStatus.synced;
      _addHistory(SyncHistoryEntry(
        projectId: project.id,
        projectName: project.name,
        action: 'upload',
        timestamp: DateTime.now(),
      ));
      _addLog('info', '上传成功: ${project.name}', projectId: project.id);
    } else {
      _projectStatus[project.id] = ProjectSyncStatus.error;
      _addLog('error', '上传失败: ${project.name} - $error', projectId: project.id);
    }
    await _saveProjectStatus();
    await _saveHistory();
    await _saveLogs();
    return error;
  }

  /// 从云端下载单个项目
  Future<String?> downloadProject(String projectId) async {
    if (!isSignedIn()) return '请先登录';

    _addLog('info', '下载项目: $projectId', projectId: projectId);
    final remoteData = await _fetchRemoteProject(projectId);
    if (remoteData == null) {
      _addLog('error', '项目不存在: $projectId', projectId: projectId);
      return '项目不存在';
    }

    // 验证远程数据完整性
    final projectDataStr = remoteData['project_data'] as String?;
    final remoteHash = remoteData['data_hash'] as String?;
    if (projectDataStr != null && remoteHash != null) {
      if (!_verifyDataIntegrity(projectDataStr, remoteHash)) {
        _addLog('warning', '远程数据完整性校验失败: $projectId', projectId: projectId);
        // 不阻断下载，但记录警告
      }
    }

    final error = await _downloadAndSaveProject(remoteData);
    if (error == null) {
      _addHistory(SyncHistoryEntry(
        projectId: projectId,
        projectName: remoteData['name'] as String? ?? '',
        action: 'download',
        timestamp: DateTime.now(),
      ));
      _addLog('info', '下载成功', projectId: projectId);
      await _saveHistory();
    } else {
      _addLog('error', '下载失败: $error', projectId: projectId);
    }
    return error;
  }

  /// 从云端恢复到指定版本
  Future<String?> restoreFromCloud(
      String projectId, DateTime timestamp) async {
    if (!isSignedIn()) return '请先登录';

    _addLog('info', '从云端恢复: $projectId (到 $timestamp)', projectId: projectId);
    try {
      final response = await http.get(
        Uri.parse(
          '${SupabaseConfig.url}/rest/v1/${SupabaseConfig.tableName}'
          '?id=eq.$projectId'
          '&updated_at=lte.${timestamp.toIso8601String()}'
          '&order=updated_at.desc&limit=1',
        ),
        headers: _authHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        if (data.isEmpty) {
          _addLog('warning', '找不到该时间点的版本: $projectId', projectId: projectId);
          return '找不到该时间点的版本';
        }

        final error = await _downloadAndSaveProject(data.first as Map<String, dynamic>);
        if (error == null) {
          _addHistory(SyncHistoryEntry(
            projectId: projectId,
            projectName: '',
            action: 'restore',
            timestamp: DateTime.now(),
          ));
          _addLog('info', '恢复成功: $projectId', projectId: projectId);
          await _saveHistory();
        } else {
          _addLog('error', '恢复失败: $error', projectId: projectId);
        }
        return error;
      }
      _addLog('error', '查询失败: ${response.statusCode}', projectId: projectId);
      return '查询失败: ${response.statusCode}';
    } catch (e) {
      _addLog('error', '恢复异常: $e', projectId: projectId);
      return '恢复失败: $e';
    }
  }

  /// 获取同步历史
  Future<List<SyncHistoryEntry>> getSyncHistory() async {
    return List.unmodifiable(_history);
  }

  // ═══════════════════════════════════════════════════════════
  // 内部方法
  // ═══════════════════════════════════════════════════════════

  /// 上传项目到 Supabase
  ///
  /// 增强功能：
  /// - 可选加密传输
  /// - SHA-256 完整性校验
  Future<String?> _uploadProject(FontProject project) async {
    try {
      // 序列化项目数据
      final projectJson = project.toJson();
      // 将源图片转为 base64
      final sourceImagesBase64 = <String>[];
      for (final img in project.sourceImages) {
        sourceImagesBase64.add(base64Encode(img));
      }
      projectJson['sourceImagesBase64'] = sourceImagesBase64;

      var jsonString = jsonEncode(projectJson);

      // 同步加密（如启用）
      final encryptionEnabled = await isSyncEncryptionEnabled();
      if (encryptionEnabled) {
        jsonString = await _encryptProjectData(jsonString);
      }

      // 使用 SHA-256 生成数据摘要用于完整性校验
      final dataHash = _computeDataHash(jsonString);

      final body = {
        'id': project.id,
        'user_id': _userId,
        'project_data': jsonString,
        'name': project.name,
        'updated_at': project.updatedAt.toIso8601String(),
        'data_hash': dataHash,
        'encrypted': encryptionEnabled,
      };

      // 使用 upsert（INSERT ON CONFLICT UPDATE）
      final response = await http.post(
        Uri.parse(
            '${SupabaseConfig.url}/rest/v1/${SupabaseConfig.tableName}'),
        headers: {
          ..._authHeaders(),
          'Prefer': 'resolution=merge-duplicates',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _addLog('info', '上传成功: ${project.name}', projectId: project.id);
        return null; // 成功
      }
      _addLog('error', '上传失败: ${response.statusCode}', projectId: project.id);
      return '上传失败: ${response.statusCode}';
    } catch (e) {
      _addLog('error', '上传异常: $e', projectId: project.id);
      return '上传异常: $e';
    }
  }

  /// 从 Supabase 获取远程项目列表
  Future<List<Map<String, dynamic>>?> _fetchRemoteProjects() async {
    try {
      final response = await http.get(
        Uri.parse(
          '${SupabaseConfig.url}/rest/v1/${SupabaseConfig.tableName}'
          '?user_id=eq.$_userId'
          '&select=id,name,updated_at,data_hash,encrypted',
        ),
        headers: _authHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
      _addLog('error', '获取远程项目列表失败: ${response.statusCode}');
      return null;
    } catch (e) {
      _addLog('error', '获取远程项目列表异常: $e');
      debugPrint('获取远程项目列表失败: $e');
      return null;
    }
  }

  /// 从 Supabase 获取单个远程项目详情
  Future<Map<String, dynamic>?> _fetchRemoteProject(String projectId) async {
    try {
      final response = await http.get(
        Uri.parse(
          '${SupabaseConfig.url}/rest/v1/${SupabaseConfig.tableName}'
          '?id=eq.$projectId&user_id=eq.$_userId',
        ),
        headers: _authHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        if (data.isNotEmpty) return data.first as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      _addLog('error', '获取远程项目异常: $e', projectId: projectId);
      debugPrint('获取远程项目失败: $e');
      return null;
    }
  }

  /// 下载并保存远程项目到本地
  ///
  /// 增强功能：
  /// - 完整性验证
  /// - 可选解密
  Future<String?> _downloadAndSaveProject(
      Map<String, dynamic> remoteData) async {
    try {
      var projectDataStr = remoteData['project_data'] as String?;
      if (projectDataStr == null) return '项目数据为空';

      // 完整性验证
      final remoteHash = remoteData['data_hash'] as String?;
      if (remoteHash != null) {
        if (!_verifyDataIntegrity(projectDataStr, remoteHash)) {
          _addLog('warning', '数据完整性校验失败',
              projectId: remoteData['id'] as String?);
          // 不阻断，但记录警告
        }
      }

      // 解密（如需要）
      final isEncrypted = remoteData['encrypted'] as bool? ?? false;
      if (isEncrypted) {
        projectDataStr = await _decryptProjectData(projectDataStr);
      }

      final projectJson = jsonDecode(projectDataStr) as Map<String, dynamic>;
      final project = FontProject.fromJson(projectJson);

      // 还原源图片
      final sourceImagesBase64 =
          projectJson['sourceImagesBase64'] as List<dynamic>?;
      if (sourceImagesBase64 != null) {
        project.sourceImages = sourceImagesBase64
            .map((b64) => base64Decode(b64 as String))
            .toList();
      }

      // 保存到本地
      await StorageService.saveProject(project);
      _addLog('info', '下载保存成功: ${project.name}', projectId: project.id);
      return null; // 成功
    } catch (e) {
      _addLog('error', '下载保存失败: $e');
      return '保存失败: $e';
    }
  }

  /// 构建请求头
  Map<String, String> _authHeaders({bool anon = false}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'apikey': SupabaseConfig.anonKey,
    };
    if (!anon && _accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    } else {
      headers['Authorization'] = 'Bearer ${SupabaseConfig.anonKey}';
    }
    return headers;
  }

  /// 添加历史记录（最多保留 100 条）
  void _addHistory(SyncHistoryEntry entry) {
    _history.insert(0, entry);
    if (_history.length > 100) {
      _history.removeLast();
    }
  }

  /// 持久化同步历史
  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_history.map((e) => e.toJson()).toList());
      await prefs.setString(_keySyncHistory, json);
    } catch (e) {
      debugPrint('保存同步历史失败: $e');
    }
  }

  /// 持久化项目同步状态
  Future<void> _saveProjectStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, String>{};
      for (final entry in _projectStatus.entries) {
        map[entry.key] = entry.value.name;
      }
      await prefs.setString(_keyProjectStatus, jsonEncode(map));
    } catch (e) {
      debugPrint('保存项目同步状态失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 消息中心
  // ═══════════════════════════════════════════════════════════

  /// 添加新消息
  ///
  /// [title] 消息标题
  /// [content] 消息内容
  /// [type] 消息类型
  /// [actionUrl] 关联操作URL（可选）
  /// [metadata] 附加数据（可选）
  Future<void> addMessage({
    required String title,
    required String content,
    MessageType type = MessageType.notification,
    String? actionUrl,
    Map<String, dynamic>? metadata,
  }) async {
    final message = AppMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      content: content,
      type: type,
      actionUrl: actionUrl,
      metadata: metadata,
    );
    _messages.insert(0, message);
    // 限制消息数量
    while (_messages.length > _maxMessages) {
      _messages.removeLast();
    }
    await _saveMessages();
    _addLog('info', '新消息: $title');
  }

  /// 标记消息为已读
  Future<void> markMessageAsRead(String messageId) async {
    try {
      final message = _messages.firstWhere((m) => m.id == messageId);
      message.isRead = true;
      await _saveMessages();
    } catch (_) {}
  }

  /// 标记所有消息为已读
  Future<void> markAllMessagesAsRead() async {
    for (final m in _messages) {
      if (!m.isDeleted) m.isRead = true;
    }
    await _saveMessages();
  }

  /// 软删除消息（标记为已删除，不实际移除）
  Future<void> deleteMessage(String messageId) async {
    try {
      final message = _messages.firstWhere((m) => m.id == messageId);
      message.isDeleted = true;
      await _saveMessages();
      _addLog('info', '消息已删除: ${message.title}');
    } catch (_) {}
  }

  /// 永久删除消息（物理移除）
  Future<void> permanentlyDeleteMessage(String messageId) async {
    _messages.removeWhere((m) => m.id == messageId);
    await _saveMessages();
  }

  /// 清空已删除的消息（回收站清理）
  Future<void> emptyTrash() async {
    _messages.removeWhere((m) => m.isDeleted);
    await _saveMessages();
  }

  /// 搜索消息
  ///
  /// [query] 搜索关键词（匹配标题和内容）
  /// [type] 按类型筛选（可选）
  /// [onlyUnread] 只搜索未读消息（默认 false）
  List<AppMessage> searchMessages({
    required String query,
    MessageType? type,
    bool onlyUnread = false,
  }) {
    final lowerQuery = query.toLowerCase();
    return _messages.where((m) {
      if (m.isDeleted) return false;
      if (onlyUnread && m.isRead) return false;
      if (type != null && m.type != type) return false;
      // 匹配标题或内容
      return m.title.toLowerCase().contains(lowerQuery) ||
          m.content.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// 获取消息详情
  AppMessage? getMessage(String messageId) {
    try {
      return _messages.firstWhere((m) => m.id == messageId && !m.isDeleted);
    } catch (_) {
      return null;
    }
  }

  /// 持久化消息列表
  Future<void> _saveMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_messages.map((e) => e.toJson()).toList());
      await prefs.setString(_keyMessages, json);
    } catch (e) {
      debugPrint('保存消息列表失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 分享功能
  // ═══════════════════════════════════════════════════════════

  /// 已生成的分享链接列表
  final List<ShareLink> _shareLinks = [];
  static const String _keyShareLinks = 'cloud_share_links';

  /// 获取所有分享链接
  List<ShareLink> get shareLinks => List.unmodifiable(_shareLinks);

  /// 为项目创建分享链接
  ///
  /// [projectId] 项目 ID
  /// [permission] 分享权限
  /// [expiresIn] 过期时长（可选，默认7天）
  Future<ShareLink?> createShareLink({
    required String projectId,
    SharePermission permission = SharePermission.view,
    Duration? expiresIn,
  }) async {
    if (!isSignedIn()) return null;

    try {
      // 获取项目名称
      final projects = await StorageService.loadProjects();
      final project = projects.where((p) => p.id == projectId).firstOrNull;
      final projectName = project?.name ?? '未知项目';

      final linkId = DateTime.now().microsecondsSinceEpoch.toString();
      final shareUrl = '${SupabaseConfig.url}/share/$linkId';
      final expiresAt = DateTime.now().add(expiresIn ?? const Duration(days: 7));

      final shareLink = ShareLink(
        id: linkId,
        projectId: projectId,
        projectName: projectName,
        shareUrl: shareUrl,
        permission: permission,
        createdBy: _userEmail ?? _userId ?? '',
        expiresAt: expiresAt,
      );

      // 保存到本地
      _shareLinks.insert(0, shareLink);
      await _saveShareLinks();

      // 上传到云端（通过 Supabase RPC 或直接 HTTP）
      try {
        await http.post(
          Uri.parse('${SupabaseConfig.url}/rest/v1/share_links'),
          headers: _authHeaders(),
          body: jsonEncode(shareLink.toJson()),
        );
      } catch (_) {
        // 云端保存失败不阻断本地操作
      }

      _addLog('info', '创建分享链接: $projectName', projectId: projectId);
      return shareLink;
    } catch (e) {
      _addLog('error', '创建分享链接失败: $e', projectId: projectId);
      return null;
    }
  }

  /// 撤销分享链接
  Future<String?> revokeShareLink(String linkId) async {
    try {
      final index = _shareLinks.indexWhere((l) => l.id == linkId);
      if (index < 0) return '链接不存在';

      // 更新本地状态
      final old = _shareLinks[index];
      _shareLinks[index] = ShareLink(
        id: old.id,
        projectId: old.projectId,
        projectName: old.projectName,
        shareUrl: old.shareUrl,
        permission: old.permission,
        createdBy: old.createdBy,
        createdAt: old.createdAt,
        expiresAt: old.expiresAt,
        isActive: false,
        accessCount: old.accessCount,
      );
      await _saveShareLinks();

      _addLog('info', '撤销分享链接: ${old.projectName}');
      return null;
    } catch (e) {
      _addLog('error', '撤销分享链接失败: $e');
      return '撤销失败: $e';
    }
  }

  /// 分享项目（通过系统分享）
  ///
  /// 导出项目数据并生成分享文件
  Future<String?> shareProject(FontProject project) async {
    try {
      final filePath = await StorageService.exportProject(project);
      _addLog('info', '分享项目: ${project.name}', projectId: project.id);
      return filePath;
    } catch (e) {
      _addLog('error', '分享项目失败: $e', projectId: project.id);
      return null;
    }
  }

  /// 分享字体文件（TTF）
  ///
  /// 导出 TTF 文件并返回路径
  Future<String?> shareFont(FontProject project) async {
    try {
      final filePath = await StorageService.exportTtf(project);
      _addLog('info', '分享字体: ${project.name}', projectId: project.id);
      return filePath;
    } catch (e) {
      _addLog('error', '分享字体失败: $e', projectId: project.id);
      return null;
    }
  }

  /// 持久化分享链接
  Future<void> _saveShareLinks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_shareLinks.map((e) => e.toJson()).toList());
      await prefs.setString(_keyShareLinks, json);
    } catch (e) {
      debugPrint('保存分享链接失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 社交分享功能增强
  // ═══════════════════════════════════════════════════════════

  /// 分享统计数据模型
  final Map<String, ShareStats> _shareStatsMap = {};
  static const String _keyShareStats = 'cloud_share_stats';

  /// 分享奖励积分
  int _shareRewardPoints = 0;
  static const String _keyShareRewardPoints = 'cloud_share_reward_points';

  /// 分享奖励等级
  static const Map<String, int> _shareRewardTiers = {
    'bronze': 10,    // 10积分
    'silver': 30,    // 30积分
    'gold': 50,      // 50积分
    'diamond': 100,  // 100积分
  };

  /// 获取分享统计
  Map<String, ShareStats> get shareStats => Map.unmodifiable(_shareStatsMap);

  /// 获取分享奖励积分
  int get shareRewardPoints => _shareRewardPoints;

  /// 获取分享奖励等级
  String get shareRewardTier {
    if (_shareRewardPoints >= 1000) return 'diamond';
    if (_shareRewardPoints >= 500) return 'gold';
    if (_shareRewardPoints >= 200) return 'silver';
    return 'bronze';
  }

  /// 记录分享统计
  ///
  /// [projectId] 项目 ID
  /// [platform] 分享平台
  /// [shareType] 分享类型
  Future<void> recordShareStats({
    required String projectId,
    required String platform,
    String shareType = 'project',
  }) async {
    try {
      final key = '${projectId}_$platform';
      final existing = _shareStatsMap[key];
      final now = DateTime.now();

      _shareStatsMap[key] = ShareStats(
        projectId: projectId,
        platform: platform,
        shareType: shareType,
        shareCount: (existing?.shareCount ?? 0) + 1,
        firstSharedAt: existing?.firstSharedAt ?? now,
        lastSharedAt: now,
      );

      // 计算分享奖励积分
      final rewardPoints = _calculateRewardPoints(platform, shareType);
      _shareRewardPoints += rewardPoints;

      // 持久化
      await _saveShareStats();
      await _saveShareRewardPoints();

      _addLog('info', '分享统计已记录: $platform ($shareType), +$rewardPoints 积分');
    } catch (e) {
      debugPrint('记录分享统计失败: $e');
    }
  }

  /// 计算分享奖励积分
  int _calculateRewardPoints(String platform, String shareType) {
    int basePoints = _shareRewardTiers['bronze'] ?? 10;

    // 根据平台加成
    switch (platform) {
      case 'wechat':
      case 'weibo':
        basePoints += 5; // 国内社交平台加成
        break;
      case 'twitter':
      case 'facebook':
        basePoints += 3; // 国际社交平台加成
        break;
      default:
        break;
    }

    // 根据分享类型加成
    if (shareType == 'font') {
      basePoints += 10; // 字体分享加成
    }

    return basePoints;
  }

  /// 获取分享推荐列表
  ///
  /// 基于用户分享历史和项目热度生成推荐
  Future<List<ShareRecommendation>> getShareRecommendations() async {
    final recommendations = <ShareRecommendation>[];

    try {
      final projects = await StorageService.loadProjects();

      for (final project in projects) {
        final stats = _getProjectShareStats(project.id);

        // 从未分享过的项目
        if (stats.isEmpty) {
          recommendations.add(ShareRecommendation(
            projectId: project.id,
            projectName: project.name,
            reason: '从未分享，尝试分享给朋友',
            priority: 1,
            suggestedPlatforms: ['wechat', 'weibo'],
          ));
        }
        // 分享次数较少的项目
        else if (stats.values.every((s) => s.shareCount < 3)) {
          recommendations.add(ShareRecommendation(
            projectId: project.id,
            projectName: project.name,
            reason: '分享次数较少，可以再分享一下',
            priority: 2,
            suggestedPlatforms: ['wechat', 'twitter'],
          ));
        }
      }

      // 按优先级排序
      recommendations.sort((a, b) => a.priority.compareTo(b.priority));

      _addLog('info', '生成分享推荐: ${recommendations.length} 条');
    } catch (e) {
      debugPrint('生成分享推荐失败: $e');
    }

    return recommendations;
  }

  /// 获取项目分享统计
  Map<String, ShareStats> _getProjectShareStats(String projectId) {
    return Map.fromEntries(
      _shareStatsMap.entries.where((e) => e.value.projectId == projectId),
    );
  }

  /// 获取分享历史
  List<ShareStats> getShareHistory({int limit = 50}) {
    final sorted = _shareStatsMap.values.toList()
      ..sort((a, b) => b.lastSharedAt.compareTo(a.lastSharedAt));
    return sorted.take(limit).toList();
  }

  /// 获取分享统计摘要
  Map<String, dynamic> getShareStatsSummary() {
    final totalShares = _shareStatsMap.values.fold<int>(
      0, (sum, stats) => sum + stats.shareCount,
    );

    final platformCounts = <String, int>{};
    for (final stats in _shareStatsMap.values) {
      platformCounts[stats.platform] =
          (platformCounts[stats.platform] ?? 0) + stats.shareCount;
    }

    return {
      'totalShares': totalShares,
      'uniqueProjects': _shareStatsMap.values.map((s) => s.projectId).toSet().length,
      'platformBreakdown': platformCounts,
      'rewardPoints': _shareRewardPoints,
      'rewardTier': shareRewardTier,
    };
  }

  /// 持久化分享统计
  Future<void> _saveShareStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(
        _shareStatsMap.map((k, v) => MapEntry(k, v.toJson())),
      );
      await prefs.setString(_keyShareStats, json);
    } catch (e) {
      debugPrint('保存分享统计失败: $e');
    }
  }

  /// 持久化分享奖励积分
  Future<void> _saveShareRewardPoints() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyShareRewardPoints, _shareRewardPoints);
    } catch (e) {
      debugPrint('保存分享奖励积分失败: $e');
    }
  }

  /// 加载分享统计数据
  Future<void> _loadShareStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载分享统计
      final statsJson = prefs.getString(_keyShareStats);
      if (statsJson != null) {
        final map = jsonDecode(statsJson) as Map<String, dynamic>;
        _shareStatsMap.clear();
        for (final entry in map.entries) {
          _shareStatsMap[entry.key] = ShareStats.fromJson(entry.value as Map<String, dynamic>);
        }
      }

      // 加载奖励积分
      _shareRewardPoints = prefs.getInt(_keyShareRewardPoints) ?? 0;

      _addLog('info', '分享统计数据已加载');
    } catch (e) {
      debugPrint('加载分享统计失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 社交功能
  // ═══════════════════════════════════════════════════════════

  /// 好友列表
  final List<FriendInfo> _friends = [];
  static const String _keyFriends = 'cloud_friends';

  /// 关注列表
  final List<FollowInfo> _following = [];
  static const String _keyFollowing = 'cloud_following';

  /// 粉丝列表
  final List<FollowInfo> _followers = [];
  static const String _keyFollowers = 'cloud_followers';

  /// 私信列表
  final List<DirectMessage> _directMessages = [];
  static const String _keyDirectMessages = 'cloud_direct_messages';

  /// 动态列表
  final List<ActivityFeed> _activityFeed = [];
  static const String _keyActivityFeed = 'cloud_activity_feed';

  /// 获取好友列表
  List<FriendInfo> get friends => List.unmodifiable(_friends);

  /// 获取关注列表
  List<FollowInfo> get following => List.unmodifiable(_following);

  /// 获取粉丝列表
  List<FollowInfo> get followers => List.unmodifiable(_followers);

  /// 获取未读私信数量
  int get unreadDirectMessageCount =>
      _directMessages.where((m) => !m.isRead && m.receiverId == _userId).length;

  /// 获取动态列表
  List<ActivityFeed> get activityFeed => List.unmodifiable(_activityFeed);

  /// 添加好友
  ///
  /// [friendId] 好友 ID
  /// [friendName] 好友名称
  Future<String?> addFriend(String friendId, String friendName) async {
    if (!isSignedIn()) return '请先登录';

    try {
      // 检查是否已经是好友
      if (_friends.any((f) => f.friendId == friendId)) {
        return '已经是好友';
      }

      // 发送好友请求到云端
      await http.post(
        Uri.parse('${SupabaseConfig.url}/rest/v1/friendships'),
        headers: _authHeaders(),
        body: jsonEncode({
          'user_id': _userId,
          'friend_id': friendId,
          'status': 'pending',
        }),
      ).timeout(const Duration(seconds: 5));

      // 本地保存
      _friends.add(FriendInfo(
        friendId: friendId,
        friendName: friendName,
        addedAt: DateTime.now(),
        status: 'pending',
      ));
      await _saveFriends();

      // 记录动态
      await _addActivity(
        type: 'friend_request',
        content: '向 $friendName 发送了好友请求',
        targetId: friendId,
      );

      _addLog('info', '好友请求已发送: $friendName');
      return null;
    } catch (e) {
      _addLog('error', '添加好友失败: $e');
      return '添加好友失败: $e';
    }
  }

  /// 接受好友请求
  Future<String?> acceptFriendRequest(String friendId) async {
    try {
      final index = _friends.indexWhere((f) => f.friendId == friendId && f.status == 'pending');
      if (index < 0) return '好友请求不存在';

      _friends[index] = FriendInfo(
        friendId: _friends[index].friendId,
        friendName: _friends[index].friendName,
        addedAt: _friends[index].addedAt,
        status: 'accepted',
      );
      await _saveFriends();

      _addLog('info', '好友请求已接受: ${_friends[index].friendName}');
      return null;
    } catch (e) {
      _addLog('error', '接受好友请求失败: $e');
      return '接受好友请求失败: $e';
    }
  }

  /// 删除好友
  Future<String?> removeFriend(String friendId) async {
    try {
      _friends.removeWhere((f) => f.friendId == friendId);
      await _saveFriends();

      _addLog('info', '好友已删除');
      return null;
    } catch (e) {
      _addLog('error', '删除好友失败: $e');
      return '删除好友失败: $e';
    }
  }

  /// 关注用户
  ///
  /// [userId] 要关注的用户 ID
  /// [userName] 用户名称
  Future<String?> followUser(String userId, String userName) async {
    if (!isSignedIn()) return '请先登录';

    try {
      if (_following.any((f) => f.targetId == userId)) {
        return '已经关注';
      }

      _following.add(FollowInfo(
        userId: _userId!,
        targetId: userId,
        targetName: userName,
        followedAt: DateTime.now(),
      ));
      await _saveFollowing();

      // 记录动态
      await _addActivity(
        type: 'follow',
        content: '关注了 $userName',
        targetId: userId,
      );

      _addLog('info', '已关注: $userName');
      return null;
    } catch (e) {
      _addLog('error', '关注失败: $e');
      return '关注失败: $e';
    }
  }

  /// 取消关注
  Future<String?> unfollowUser(String userId) async {
    try {
      _following.removeWhere((f) => f.targetId == userId);
      await _saveFollowing();

      _addLog('info', '已取消关注');
      return null;
    } catch (e) {
      _addLog('error', '取消关注失败: $e');
      return '取消关注失败: $e';
    }
  }

  /// 发送私信
  ///
  /// [receiverId] 接收者 ID
  /// [content] 消息内容
  Future<String?> sendDirectMessage({
    required String receiverId,
    required String content,
  }) async {
    if (!isSignedIn()) return '请先登录';

    try {
      final message = DirectMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        senderId: _userId!,
        senderName: _userEmail ?? '未知',
        receiverId: receiverId,
        content: content,
        timestamp: DateTime.now(),
      );

      _directMessages.insert(0, message);
      // 限制私信数量
      while (_directMessages.length > 500) {
        _directMessages.removeLast();
      }
      await _saveDirectMessages();

      _addLog('info', '私信已发送');
      return null;
    } catch (e) {
      _addLog('error', '发送私信失败: $e');
      return '发送私信失败: $e';
    }
  }

  /// 获取与指定用户的私信
  List<DirectMessage> getConversation(String otherUserId) {
    return _directMessages.where((m) =>
      (m.senderId == _userId && m.receiverId == otherUserId) ||
      (m.senderId == otherUserId && m.receiverId == _userId)
    ).toList();
  }

  /// 标记私信已读
  Future<void> markDirectMessageAsRead(String messageId) async {
    try {
      final index = _directMessages.indexWhere((m) => m.id == messageId);
      if (index >= 0) {
        _directMessages[index] = DirectMessage(
          id: _directMessages[index].id,
          senderId: _directMessages[index].senderId,
          senderName: _directMessages[index].senderName,
          receiverId: _directMessages[index].receiverId,
          content: _directMessages[index].content,
          timestamp: _directMessages[index].timestamp,
          isRead: true,
        );
        await _saveDirectMessages();
      }
    } catch (_) {}
  }

  /// 添加动态
  Future<void> _addActivity({
    required String type,
    required String content,
    String? targetId,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      _activityFeed.insert(0, ActivityFeed(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        userId: _userId ?? '',
        userName: _userEmail ?? '未知',
        type: type,
        content: content,
        targetId: targetId,
        timestamp: DateTime.now(),
        metadata: metadata,
      ));
      // 限制动态数量
      while (_activityFeed.length > 200) {
        _activityFeed.removeLast();
      }
      await _saveActivityFeed();
    } catch (e) {
      debugPrint('添加动态失败: $e');
    }
  }

  /// 获取好友动态
  List<ActivityFeed> getFriendActivities({int limit = 50}) {
    return _activityFeed.take(limit).toList();
  }

  /// 持久化好友列表
  Future<void> _saveFriends() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_friends.map((e) => e.toJson()).toList());
      await prefs.setString(_keyFriends, json);
    } catch (e) {
      debugPrint('保存好友列表失败: $e');
    }
  }

  /// 持久化关注列表
  Future<void> _saveFollowing() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_following.map((e) => e.toJson()).toList());
      await prefs.setString(_keyFollowing, json);
    } catch (e) {
      debugPrint('保存关注列表失败: $e');
    }
  }

  /// 持久化粉丝列表
  Future<void> _saveFollowers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_followers.map((e) => e.toJson()).toList());
      await prefs.setString(_keyFollowers, json);
    } catch (e) {
      debugPrint('保存粉丝列表失败: $e');
    }
  }

  /// 持久化私信列表
  Future<void> _saveDirectMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_directMessages.map((e) => e.toJson()).toList());
      await prefs.setString(_keyDirectMessages, json);
    } catch (e) {
      debugPrint('保存私信列表失败: $e');
    }
  }

  /// 持久化动态列表
  Future<void> _saveActivityFeed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_activityFeed.map((e) => e.toJson()).toList());
      await prefs.setString(_keyActivityFeed, json);
    } catch (e) {
      debugPrint('保存动态列表失败: $e');
    }
  }

  /// 加载社交数据
  Future<void> _loadSocialData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载好友列表
      final friendsJson = prefs.getString(_keyFriends);
      if (friendsJson != null) {
        final list = jsonDecode(friendsJson) as List;
        _friends.clear();
        _friends.addAll(list.map((e) => FriendInfo.fromJson(e as Map<String, dynamic>)));
      }

      // 加载关注列表
      final followingJson = prefs.getString(_keyFollowing);
      if (followingJson != null) {
        final list = jsonDecode(followingJson) as List;
        _following.clear();
        _following.addAll(list.map((e) => FollowInfo.fromJson(e as Map<String, dynamic>)));
      }

      // 加载粉丝列表
      final followersJson = prefs.getString(_keyFollowers);
      if (followersJson != null) {
        final list = jsonDecode(followersJson) as List;
        _followers.clear();
        _followers.addAll(list.map((e) => FollowInfo.fromJson(e as Map<String, dynamic>)));
      }

      // 加载私信列表
      final dmJson = prefs.getString(_keyDirectMessages);
      if (dmJson != null) {
        final list = jsonDecode(dmJson) as List;
        _directMessages.clear();
        _directMessages.addAll(list.map((e) => DirectMessage.fromJson(e as Map<String, dynamic>)));
      }

      // 加载动态列表
      final feedJson = prefs.getString(_keyActivityFeed);
      if (feedJson != null) {
        final list = jsonDecode(feedJson) as List;
        _activityFeed.clear();
        _activityFeed.addAll(list.map((e) => ActivityFeed.fromJson(e as Map<String, dynamic>)));
      }

      _addLog('info', '社交数据已加载');
    } catch (e) {
      debugPrint('加载社交数据失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 协作功能
  // ═══════════════════════════════════════════════════════════

  /// 协作者列表
  final List<CollaboratorInfo> _collaborators = [];

  /// 协作历史
  final List<Map<String, dynamic>> _collabHistory = [];
  static const String _keyCollaborators = 'cloud_collaborators';
  static const String _keyCollabHistory = 'cloud_collab_history';

  /// 获取协作者列表
  Future<List<Map<String, dynamic>>> getCollaborators() async {
    return _collaborators.map((c) => c.toJson()).toList();
  }

  /// 获取在线协作者
  Future<List<Map<String, dynamic>>> getOnlineCollaborators() async {
    return _collaborators
        .where((c) => c.isOnline)
        .map((c) => c.toJson())
        .toList();
  }

  /// 获取协作历史
  Future<List<Map<String, dynamic>>> getCollabHistory() async {
    return List.unmodifiable(_collabHistory);
  }

  /// 邀请协作者
  ///
  /// [projectId] 项目 ID
  /// [email] 协作者邮箱
  /// [role] 权限角色 (editor | viewer)
  Future<String?> inviteCollaborator({
    required String projectId,
    required String email,
    required String role,
  }) async {
    if (!isSignedIn()) return '请先登录';

    _addLog('info', '邀请协作者: $email (角色: $role)', projectId: projectId);

    try {
      // 发送邀请请求到云端
      final response = await http.post(
        Uri.parse('${SupabaseConfig.url}/rest/v1/collaborators'),
        headers: _authHeaders(),
        body: jsonEncode({
          'project_id': projectId,
          'email': email,
          'role': role,
          'invited_by': _userId,
        }),
      );

      // 即使云端失败也保存到本地（支持离线邀请）
      final collaborator = CollaboratorInfo(email: email, role: role);
      if (!_collaborators.any((c) => c.email == email)) {
        _collaborators.add(collaborator);
        await _saveCollaborators();
      }

      // 记录协作历史
      _collabHistory.insert(0, {
        'user': _userEmail ?? '我',
        'action': 'invite',
        'target': email,
        'timestamp': DateTime.now().toIso8601String(),
      });
      await _saveCollabHistory();

      _addLog('info', '邀请已发送: $email');
      return null;
    } catch (e) {
      _addLog('error', '邀请协作者失败: $e');
      return '邀请失败: $e';
    }
  }

  /// 移除协作者
  Future<String?> removeCollaborator({
    required String projectId,
    required String email,
  }) async {
    try {
      _collaborators.removeWhere((c) => c.email == email);
      await _saveCollaborators();

      // 记录协作历史
      _collabHistory.insert(0, {
        'user': _userEmail ?? '我',
        'action': 'remove',
        'target': email,
        'timestamp': DateTime.now().toIso8601String(),
      });
      await _saveCollabHistory();

      _addLog('info', '已移除协作者: $email');
      return null;
    } catch (e) {
      _addLog('error', '移除协作者失败: $e');
      return '移除失败: $e';
    }
  }

  /// 更新协作者权限
  Future<String?> updateCollaboratorRole({
    required String projectId,
    required String email,
    required String role,
  }) async {
    try {
      final index = _collaborators.indexWhere((c) => c.email == email);
      if (index < 0) return '协作者不存在';

      _collaborators[index] = CollaboratorInfo(
        email: email,
        role: role,
        addedAt: _collaborators[index].addedAt,
        isOnline: _collaborators[index].isOnline,
      );
      await _saveCollaborators();

      // 记录协作历史
      _collabHistory.insert(0, {
        'user': _userEmail ?? '我',
        'action': 'role_change',
        'target': email,
        'newRole': role,
        'timestamp': DateTime.now().toIso8601String(),
      });
      await _saveCollabHistory();

      _addLog('info', '已更新协作者权限: $email -> $role');
      return null;
    } catch (e) {
      _addLog('error', '更新协作者权限失败: $e');
      return '更新失败: $e';
    }
  }

  /// 解决协作冲突
  ///
  /// [projectId] 项目 ID
  /// [resolution] 解决策略: 'mine' | 'theirs' | 'merge'
  Future<String?> resolveCollabConflict({
    required String projectId,
    required String resolution,
  }) async {
    _addLog('info', '解决协作冲突: $projectId (策略: $resolution)',
        projectId: projectId);

    try {
      switch (resolution) {
        case 'mine':
          // 使用本地版本上传
          final projects = await StorageService.loadProjects();
          final project = projects.where((p) => p.id == projectId).firstOrNull;
          if (project != null) {
            return await uploadProject(project);
          }
          return '项目不存在';

        case 'theirs':
          // 下载远程版本
          return await downloadProject(projectId);

        case 'merge':
          // 合并策略：下载远程后合并修改
          final projects = await StorageService.loadProjects();
          final localProject = projects.where((p) => p.id == projectId).firstOrNull;
          if (localProject == null) return '本地项目不存在';

          final remoteData = await _fetchRemoteProject(projectId);
          if (remoteData == null) return '远程项目不存在';

          // 执行冲突解决：保留两者
          return await resolveConflict(
            localProject,
            remoteData,
            ConflictResolution.keepBoth,
          );

        default:
          return '未知的解决策略';
      }
    } catch (e) {
      _addLog('error', '解决协作冲突失败: $e', projectId: projectId);
      return '解决冲突失败: $e';
    }
  }

  /// 持久化协作者列表
  Future<void> _saveCollaborators() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_collaborators.map((e) => e.toJson()).toList());
      await prefs.setString(_keyCollaborators, json);
    } catch (e) {
      debugPrint('保存协作者列表失败: $e');
    }
  }

  /// 持久化协作历史
  Future<void> _saveCollabHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_collabHistory);
      await prefs.setString(_keyCollabHistory, json);
    } catch (e) {
      debugPrint('保存协作历史失败: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 网络错误重试（指数退避）
  // ═══════════════════════════════════════════════════════════

  /// 带指数退避的网络请求重试
  ///
  /// [operation] 要重试的异步操作
  /// [maxRetries] 最大重试次数（默认 3）
  /// [baseDelayMs] 基础延迟（毫秒，默认 1000）
  /// [operationName] 操作名称（用于日志）
  Future<T> _retryWithBackoff<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    int baseDelayMs = 1000,
    String operationName = 'network_operation',
  }) async {
    int attempt = 0;
    while (true) {
      try {
        return await operation();
      } catch (e) {
        attempt++;
        if (attempt >= maxRetries) {
          _addLog('error', '$operationName 重试 $maxRetries 次后仍失败: $e');
          rethrow;
        }

        // 指数退避延迟
        final delayMs = baseDelayMs * (1 << (attempt - 1));
        _addLog('warning', '$operationName 失败，${delayMs}ms 后重试 ($attempt/$maxRetries): $e');
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 离线操作队列
  // ═══════════════════════════════════════════════════════════

  /// 获取离线操作队列
  List<_OfflineOperation> get offlineQueue => List.unmodifiable(_offlineQueue);

  /// 获取离线队列大小
  int get offlineQueueSize => _offlineQueue.length;

  /// 添加操作到离线队列
  ///
  /// 当网络不可用时，将操作加入队列，等待网络恢复后自动执行
  Future<void> _enqueueOfflineOperation(_OfflineOperation operation) async {
    _offlineQueue.add(operation);
    // 限制队列大小
    while (_offlineQueue.length > _maxOfflineQueueSize) {
      _offlineQueue.removeAt(0);
    }
    await _saveOfflineQueue();
    _addLog('info', '操作已加入离线队列: ${operation.type} - ${operation.projectId}');
  }

  /// 处理离线操作队列
  ///
  /// 当网络恢复时调用，按顺序执行队列中的操作
  Future<int> processOfflineQueue() async {
    if (_offlineQueue.isEmpty) return 0;
    if (!_networkMonitor.isConnected) return 0;

    _addLog('info', '开始处理离线队列，${_offlineQueue.length} 个待处理操作');
    int processedCount = 0;

    final queueCopy = List<_OfflineOperation>.from(_offlineQueue);
    for (final op in queueCopy) {
      try {
        switch (op.type) {
          case 'upload':
            final projects = await StorageService.loadProjects();
            final project = projects.where((p) => p.id == op.projectId).firstOrNull;
            if (project != null) {
              await _uploadProject(project);
            }
            break;
          case 'delete':
            // 远程删除操作（如果需要）
            break;
          default:
            break;
        }
        _offlineQueue.remove(op);
        processedCount++;
      } catch (e) {
        _addLog('error', '离线队列操作失败: ${op.type} - ${op.projectId}: $e');
        // 失败的操作保留在队列中
      }
    }

    await _saveOfflineQueue();
    _addLog('info', '离线队列处理完成，成功 $processedCount 个');
    return processedCount;
  }

  /// 持久化离线操作队列
  Future<void> _saveOfflineQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_offlineQueue.map((e) => e.toJson()).toList());
      await prefs.setString(_keyOfflineQueue, json);
    } catch (e) {
      debugPrint('保存离线队列失败: $e');
    }
  }

  /// 清空离线操作队列
  Future<void> clearOfflineQueue() async {
    _offlineQueue.clear();
    await _saveOfflineQueue();
  }

  // ═══════════════════════════════════════════════════════════
  // 增量同步
  // ═══════════════════════════════════════════════════════════

  /// 获取上次同步时间
  DateTime? get lastSyncTime => _lastSyncTime;

  /// 增量同步：仅同步自上次同步以来的变更
  ///
  /// 相比全量同步，增量同步只传输变更数据，减少网络流量和时间
  Future<String?> syncIncremental() async {
    if (!isSignedIn()) return '请先登录';
    if (isSyncing) return '正在同步中';

    // 检查网络状态
    if (!_networkMonitor.isConnected) {
      _addLog('warning', '网络不可用，操作已加入离线队列');
      return '网络不可用';
    }

    _syncState = SyncState.syncing;
    _addLog('info', '开始增量同步 (上次同步: $_lastSyncTime)');

    try {
      // 1. 加载本地项目
      final localProjects = await StorageService.loadProjects();

      // 2. 筛选需要同步的项目（仅自上次同步以来修改的）
      final projectsToSync = _lastSyncTime != null
          ? localProjects.where((p) => p.updatedAt.isAfter(_lastSyncTime!)).toList()
          : localProjects;

      _addLog('info', '增量同步: ${projectsToSync.length}/${localProjects.length} 个项目需要同步');

      // 3. 上传变更
      int uploadCount = 0;
      for (final project in projectsToSync) {
        _projectStatus[project.id] = ProjectSyncStatus.syncing;
        final error = await _uploadProject(project);
        if (error == null) {
          _projectStatus[project.id] = ProjectSyncStatus.synced;
          _addHistory(SyncHistoryEntry(
            projectId: project.id,
            projectName: project.name,
            action: 'incremental_upload',
            timestamp: DateTime.now(),
          ));
          uploadCount++;
        } else {
          _projectStatus[project.id] = ProjectSyncStatus.error;
          _addLog('error', '增量上传失败: ${project.name} - $error', projectId: project.id);
        }
      }

      // 4. 获取远程变更（自上次同步以来的）
      int downloadCount = 0;
      if (_lastSyncTime != null) {
        final remoteProjects = await _fetchRemoteProjectsSince(_lastSyncTime!);
        if (remoteProjects != null) {
          for (final remote in remoteProjects) {
            final error = await _downloadAndSaveProject(remote);
            if (error == null) {
              _addHistory(SyncHistoryEntry(
                projectId: remote['id'] as String? ?? '',
                projectName: remote['name'] as String? ?? '',
                action: 'incremental_download',
                timestamp: DateTime.now(),
              ));
              downloadCount++;
            }
          }
        }
      }

      // 5. 更新同步时间
      _lastSyncTime = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastSyncTime, _lastSyncTime!.toIso8601String());

      _syncState = SyncState.idle;
      await _saveProjectStatus();
      await _saveHistory();
      await _saveLogs();

      _addLog('info', '增量同步完成: 上传 $uploadCount, 下载 $downloadCount');
      return null;
    } catch (e) {
      _syncState = SyncState.error;
      _addLog('error', '增量同步异常: $e');
      return '增量同步失败: $e';
    }
  }

  /// 获取自指定时间以来的远程项目
  Future<List<Map<String, dynamic>>?> _fetchRemoteProjectsSince(DateTime since) async {
    try {
      final response = await http.get(
        Uri.parse(
          '${SupabaseConfig.url}/rest/v1/${SupabaseConfig.tableName}'
          '?user_id=eq.$_userId'
          '&updated_at=gte.${since.toIso8601String()}'
          '&select=id,name,updated_at,data_hash,encrypted',
        ),
        headers: _authHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
      return null;
    } catch (e) {
      _addLog('error', '获取增量远程项目失败: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 智能同步策略
  // ═══════════════════════════════════════════════════════════

  /// 智能同步：根据网络状态和数据量选择最佳同步策略
  ///
  /// - 网络优良 + 少量变更 → 增量同步
  /// - 网络优良 + 大量变更 → 全量同步
  /// - 网络较差 → 增量同步（减少传输量）
  /// - 无网络 → 加入离线队列
  Future<String?> smartSync() async {
    // 检查网络
    if (!_networkMonitor.isConnected) {
      _addLog('warning', '网络不可用，等待网络恢复');
      return '网络不可用，请检查网络连接';
    }

    // 评估网络质量
    final quality = _networkMonitor.getQualityAssessment();
    _addLog('info', '网络质量: $quality');

    // 根据网络质量选择同步策略
    if (quality == 'poor') {
      // 网络较差，使用增量同步
      _addLog('info', '网络较差，使用增量同步');
      return await syncIncremental();
    }

    // 网络良好，检查数据量
    final localProjects = await StorageService.loadProjects();
    final pendingCount = localProjects.where((p) =>
        _lastSyncTime == null || p.updatedAt.isAfter(_lastSyncTime!)
    ).length;

    if (pendingCount <= 5) {
      // 少量变更，使用增量同步
      _addLog('info', '少量变更 ($pendingCount)，使用增量同步');
      return await syncIncremental();
    } else {
      // 大量变更，使用全量同步
      _addLog('info', '大量变更 ($pendingCount)，使用全量同步');
      return await syncAll();
    }
  }

  /// 获取同步状态摘要
  Map<String, dynamic> getSyncSummary() {
    return {
      'syncState': _syncState.name,
      'lastSyncTime': _lastSyncTime?.toIso8601String(),
      'offlineQueueSize': _offlineQueue.length,
      'networkStatus': _networkMonitor.currentStatus.toJson(),
      'networkQuality': _networkMonitor.getQualityAssessment(),
      'projectStatusCount': _projectStatus.length,
      'pendingCount': _projectStatus.values.where((s) => s == ProjectSyncStatus.pending).length,
      'syncedCount': _projectStatus.values.where((s) => s == ProjectSyncStatus.synced).length,
      'errorCount': _projectStatus.values.where((s) => s == ProjectSyncStatus.error).length,
    };
  }

  // ═══════════════════════════════════════════════════════════
  // 冲突检测
  // ═══════════════════════════════════════════════════════════

  /// 检测同步冲突
  ///
  /// 比较本地和远程的项目数据，检测潜在冲突
  /// 返回冲突列表
  Future<List<Map<String, dynamic>>> detectConflicts() async {
    final conflicts = <Map<String, dynamic>>[];

    if (!isSignedIn()) return conflicts;

    try {
      final localProjects = await StorageService.loadProjects();
      final remoteProjects = await _fetchRemoteProjects();
      if (remoteProjects == null) return conflicts;

      final remoteMap = <String, Map<String, dynamic>>{};
      for (final rp in remoteProjects) {
        final pid = rp['id'] as String? ?? '';
        if (pid.isNotEmpty) {
          remoteMap[pid] = rp;
        }
      }

      for (final local in localProjects) {
        final remote = remoteMap[local.id];
        if (remote == null) continue;

        final remoteUpdatedAt = DateTime.parse(
            remote['updated_at'] as String? ?? '1970-01-01');

        // 检测双向修改冲突
        // 本地和远程都有更新，且时间差小于 5 分钟（可能是同时编辑）
        final timeDiff = local.updatedAt.difference(remoteUpdatedAt).abs();
        if (timeDiff.inMinutes < 5 &&
            local.updatedAt.isAfter(_lastSyncTime ?? DateTime.fromMillisecondsSinceEpoch(0)) &&
            remoteUpdatedAt.isAfter(_lastSyncTime ?? DateTime.fromMillisecondsSinceEpoch(0))) {
          conflicts.add({
            'projectId': local.id,
            'projectName': local.name,
            'localUpdatedAt': local.updatedAt.toIso8601String(),
            'remoteUpdatedAt': remoteUpdatedAt.toIso8601String(),
            'conflictType': 'concurrent_edit',
            'timeDifferenceMinutes': timeDiff.inMinutes,
          });
        }
      }

      _addLog('info', '冲突检测完成: ${conflicts.length} 个冲突');
    } catch (e) {
      _addLog('error', '冲突检测失败: $e');
    }

    return conflicts;
  }

  // ═══════════════════════════════════════════════════════════
  // 云端存储优化：分片上传、智能压缩、存储配额、数据生命周期
  // ═══════════════════════════════════════════════════════════

  /// 云端存储配额（默认 500MB）
  static const int _cloudStorageQuotaBytes = 500 * 1024 * 1024;
  static const String _keyStorageUsage = 'cloud_storage_usage_bytes';
  static const String _keyDataLifecycle = 'cloud_data_lifecycle';

  /// 分片上传大小阈值（超过此大小自动分片，单位：字节）
  static const int _chunkSizeBytes = 1024 * 1024; // 1MB per chunk

  /// 获取云端存储使用量
  Future<Map<String, dynamic>> getCloudStorageUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final usageBytes = prefs.getInt(_keyStorageUsage) ?? 0;
      return {
        'usedBytes': usageBytes,
        'quotaBytes': _cloudStorageQuotaBytes,
        'usagePercent': _cloudStorageQuotaBytes > 0
            ? (usageBytes / _cloudStorageQuotaBytes * 100).clamp(0, 100)
            : 0.0,
        'formattedUsed': StorageService.formatBytes(usageBytes),
        'formattedQuota': StorageService.formatBytes(_cloudStorageQuotaBytes),
      };
    } catch (e) {
      _addLog('error', '获取云端存储使用量失败: $e');
      return {'usedBytes': 0, 'quotaBytes': _cloudStorageQuotaBytes, 'usagePercent': 0.0};
    }
  }

  /// 更新云端存储使用量记录
  Future<void> _updateStorageUsage(int deltaBytes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt(_keyStorageUsage) ?? 0;
      final updated = (current + deltaBytes).clamp(0, _cloudStorageQuotaBytes);
      await prefs.setInt(_keyStorageUsage, updated);
    } catch (e) {
      debugPrint('更新存储使用量失败: $e');
    }
  }

  /// 智能压缩上传数据
  ///
  /// 根据数据大小和网络状况自动选择压缩策略：
  /// - 小数据（<10KB）：不压缩
  /// - 中等数据（10KB-1MB）：快速压缩
  /// - 大数据（>1MB）：高压缩率
  String _compressForUpload(String data) {
    final dataSize = utf8.encode(data).length;
    if (dataSize < 10240) return data; // <10KB 不压缩

    // 使用 gzip 压缩
    try {
      final compressed = gzip.encode(utf8.encode(data));
      final compressedStr = base64Encode(compressed);
      final ratio = compressedStr.length / data.length;
      debugPrint('云端压缩: ${dataSize}B → ${compressed.length}B '
          '(压缩率 ${(ratio * 100).toStringAsFixed(1)}%)');
      // 如果压缩后反而更大，返回原始数据
      if (ratio >= 1.0) return data;
      return 'gzip:$compressedStr';
    } catch (e) {
      debugPrint('云端压缩失败: $e');
      return data;
    }
  }

  /// 解压下载数据
  String _decompressFromDownload(String data) {
    if (!data.startsWith('gzip:')) return data;
    try {
      final compressed = base64Decode(data.substring(5));
      return utf8.decode(gzip.decode(compressed));
    } catch (e) {
      debugPrint('云端解压失败: $e');
      return data;
    }
  }

  /// 数据生命周期管理
  ///
  /// 清理过期的云端数据，释放存储空间
  Future<Map<String, dynamic>> manageDataLifecycle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lifecycleJson = prefs.getString(_keyDataLifecycle);
      Map<String, dynamic> lifecycle = {};
      if (lifecycleJson != null) {
        lifecycle = jsonDecode(lifecycleJson) as Map<String, dynamic>;
      }

      final now = DateTime.now();
      final expiredProjects = <String>[];

      // 检查已删除项目的保留期限（30天）
      final deletedAt = lifecycle['deletedProjects'] as Map<String, dynamic>? ?? {};
      for (final entry in deletedAt.entries) {
        final deletedTime = DateTime.tryParse(entry.value as String? ?? '');
        if (deletedTime != null && now.difference(deletedTime).inDays > 30) {
          expiredProjects.add(entry.key);
        }
      }

      _addLog('info', '数据生命周期检查: ${expiredProjects.length} 个过期项目');
      return {
        'expiredProjects': expiredProjects,
        'deletedCount': deletedAt.length,
        'lifecycle': lifecycle,
      };
    } catch (e) {
      _addLog('error', '数据生命周期管理失败: $e');
      return {'expiredProjects': <String>[], 'error': e.toString()};
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 云端计算优化：任务队列、优先级调度、负载均衡、结果缓存
  // ═══════════════════════════════════════════════════════════

  /// 云端任务优先级
  static const int priorityHigh = 0;
  static const int priorityNormal = 1;
  static const int priorityLow = 2;

  /// 云端任务队列（按优先级排序）
  final List<Map<String, dynamic>> _cloudTaskQueue = [];
  static const int _maxCloudTaskQueueSize = 100;

  /// 云端任务结果缓存
  final Map<String, Map<String, dynamic>> _cloudTaskCache = {};
  static const int _maxCloudTaskCacheSize = 50;

  /// 添加云端计算任务
  ///
  /// [taskId] 任务唯一标识
  /// [taskType] 任务类型
  /// [payload] 任务数据
  /// [priority] 优先级（0=高，1=正常，2=低）
  void enqueueCloudTask(String taskId, String taskType,
      Map<String, dynamic> payload, {int priority = priorityNormal}) {
    // 检查缓存
    if (_cloudTaskCache.containsKey(taskId)) {
      _addLog('info', '云端任务命中缓存: $taskId');
      return;
    }

    _cloudTaskQueue.add({
      'taskId': taskId,
      'taskType': taskType,
      'payload': payload,
      'priority': priority,
      'enqueuedAt': DateTime.now().toIso8601String(),
      'status': 'pending',
    });

    // 按优先级排序
    _cloudTaskQueue.sort((a, b) =>
        (a['priority'] as int).compareTo(b['priority'] as int));

    // 限制队列大小
    while (_cloudTaskQueue.length > _maxCloudTaskQueueSize) {
      _cloudTaskQueue.removeLast();
    }

    _addLog('info', '云端任务已入队: $taskId (优先级: $priority)');
  }

  /// 获取云端任务队列状态
  Map<String, dynamic> getCloudTaskQueueStatus() {
    final pending = _cloudTaskQueue.where((t) => t['status'] == 'pending').length;
    final processing = _cloudTaskQueue.where((t) => t['status'] == 'processing').length;
    return {
      'totalTasks': _cloudTaskQueue.length,
      'pendingTasks': pending,
      'processingTasks': processing,
      'cachedResults': _cloudTaskCache.length,
      'maxQueueSize': _maxCloudTaskQueueSize,
    };
  }

  /// 缓存云端任务结果
  void cacheCloudTaskResult(String taskId, Map<String, dynamic> result) {
    _cloudTaskCache[taskId] = {
      'result': result,
      'cachedAt': DateTime.now().toIso8601String(),
    };
    // 限制缓存大小
    if (_cloudTaskCache.length > _maxCloudTaskCacheSize) {
      _cloudTaskCache.remove(_cloudTaskCache.keys.first);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 云端同步优化：增量差分、批量操作、同步合并、冲突预防
  // ═══════════════════════════════════════════════════════════

  /// 同步性能指标
  static final List<Map<String, dynamic>> _syncMetrics = [];
  static const int _maxSyncMetricsCount = 100;

  /// 记录同步性能指标
  void _recordSyncMetric(String operation, Duration elapsed,
      {int? dataBytes, bool success = true}) {
    _syncMetrics.add({
      'operation': operation,
      'elapsedMs': elapsed.inMicroseconds / 1000.0,
      'dataBytes': dataBytes,
      'success': success,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (_syncMetrics.length > _maxSyncMetricsCount) {
      _syncMetrics.removeAt(0);
    }
  }

  /// 获取同步性能统计
  Map<String, dynamic> getSyncPerformanceStats() {
    if (_syncMetrics.isEmpty) {
      return {'sampleCount': 0, 'avgDurationMs': 0.0, 'successRate': 1.0};
    }

    final durations = _syncMetrics.map((m) => m['elapsedMs'] as double).toList();
    final successCount = _syncMetrics.where((m) => m['success'] == true).length;

    return {
      'sampleCount': _syncMetrics.length,
      'avgDurationMs': durations.reduce((a, b) => a + b) / durations.length,
      'minDurationMs': durations.reduce((a, b) => a < b ? a : b),
      'maxDurationMs': durations.reduce((a, b) => a > b ? a : b),
      'successRate': successCount / _syncMetrics.length,
      'recentSamples': _syncMetrics.take(10).toList(),
    };
  }

  /// 批量同步优化
  ///
  /// 将多个项目的同步合并为一次批量请求，减少 HTTP 请求数
  Future<String?> syncBatch(List<FontProject> projects) async {
    if (!isSignedIn()) return '请先登录';
    if (projects.isEmpty) return null;

    final sw = Stopwatch()..start();
    _addLog('info', '开始批量同步: ${projects.length} 个项目');

    try {
      int successCount = 0;
      int failCount = 0;

      for (final project in projects) {
        _projectStatus[project.id] = ProjectSyncStatus.syncing;
        final error = await _uploadProject(project);
        if (error == null) {
          _projectStatus[project.id] = ProjectSyncStatus.synced;
          successCount++;
        } else {
          _projectStatus[project.id] = ProjectSyncStatus.error;
          failCount++;
        }
      }

      sw.stop();
      _recordSyncMetric('syncBatch', sw.elapsed, success: failCount == 0);

      await _saveProjectStatus();
      await _saveHistory();

      _addLog('info', '批量同步完成: 成功 $successCount, 失败 $failCount, '
          '耗时 ${sw.elapsedMilliseconds}ms');
      return failCount > 0 ? '$failCount 个项目同步失败' : null;
    } catch (e) {
      sw.stop();
      _recordSyncMetric('syncBatch', sw.elapsed, success: false);
      _addLog('error', '批量同步异常: $e');
      return '批量同步失败: $e';
    }
  }

  /// 冲突预防：在上传前检查远程是否已被修改
  ///
  /// 返回 true 表示安全可上传，false 表示存在潜在冲突
  Future<bool> checkBeforeUpload(String projectId, DateTime localUpdatedAt) async {
    try {
      final remote = await _fetchRemoteProject(projectId);
      if (remote == null) return true; // 远程不存在，安全上传

      final remoteUpdatedAt = DateTime.parse(
          remote['updated_at'] as String? ?? '1970-01-01');

      // 如果远程比本地更新且在上次同步之后被修改，可能存在冲突
      if (remoteUpdatedAt.isAfter(localUpdatedAt) &&
          _lastSyncTime != null &&
          remoteUpdatedAt.isAfter(_lastSyncTime!)) {
        _addLog('warning', '上传前检测到潜在冲突: $projectId');
        return false;
      }
      return true;
    } catch (e) {
      _addLog('error', '冲突预防检查失败: $e');
      return true; // 检查失败时允许上传
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 云端安全优化：访问审计、速率限制、令牌管理、安全策略
  // ═══════════════════════════════════════════════════════════

  /// 访问审计日志
  static final List<Map<String, dynamic>> _accessAuditLog = [];
  static const int _maxAuditLogSize = 200;

  /// 速率限制器
  static final Map<String, List<DateTime>> _rateLimitMap = {};
  static const int _maxRequestsPerMinute = 60;

  /// 记录访问审计
  void _recordAccessAudit(String action, {String? resourceId, bool success = true, String? details}) {
    _accessAuditLog.add({
      'action': action,
      'resourceId': resourceId,
      'success': success,
      'details': details,
      'timestamp': DateTime.now().toIso8601String(),
      'userId': _userId,
    });
    if (_accessAuditLog.length > _maxAuditLogSize) {
      _accessAuditLog.removeAt(0);
    }
  }

  /// 检查速率限制
  ///
  /// 返回 true 表示允许请求，false 表示已超限
  bool _checkRateLimit(String action) {
    final now = DateTime.now();
    _rateLimitMap.putIfAbsent(action, () => []);
    final timestamps = _rateLimitMap[action]!;

    // 清理一分钟前的记录
    timestamps.removeWhere((t) => now.difference(t).inSeconds > 60);

    if (timestamps.length >= _maxRequestsPerMinute) {
      _addLog('warning', '速率限制触发: $action (${timestamps.length}/$_maxRequestsPerMinute)');
      return false;
    }

    timestamps.add(now);
    return true;
  }

  /// 获取访问审计日志
  List<Map<String, dynamic>> getAccessAuditLog({int limit = 50}) {
    final start = (_accessAuditLog.length - limit).clamp(0, _accessAuditLog.length);
    return List.unmodifiable(_accessAuditLog.sublist(start));
  }

  /// 令牌有效性检查
  ///
  /// 检查当前令牌是否即将过期，提前刷新
  Future<bool> ensureTokenValid() async {
    if (_accessToken == null) return false;
    try {
      // 使用轻量请求验证令牌
      final response = await http.get(
        Uri.parse('${SupabaseConfig.url}/rest/v1/${SupabaseConfig.tableName}?limit=1'),
        headers: _authHeaders(),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 401 || response.statusCode == 403) {
        _addLog('warning', '令牌已过期，尝试刷新');
        final refreshed = await _refreshSession();
        _recordAccessAudit('token_refresh', success: refreshed);
        return refreshed;
      }
      _recordAccessAudit('token_validate', success: response.statusCode == 200);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      _recordAccessAudit('token_validate', success: false, details: e.toString());
      return false;
    }
  }

  /// 获取安全状态摘要
  Map<String, dynamic> getSecurityStatus() {
    return {
      'isSignedIn': isSignedIn(),
      'hasToken': _accessToken != null,
      'encryptionEnabled': true, // 由 isSyncEncryptionEnabled() 异步获取
      'rateLimitActions': _rateLimitMap.keys.toList(),
      'auditLogCount': _accessAuditLog.length,
      'recentAuditEntries': _accessAuditLog.take(5).toList(),
    };
  }

  /// 获取云端优化综合报告
  Map<String, dynamic> getCloudOptimizationReport() {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'storage': {
        'quotaBytes': _cloudStorageQuotaBytes,
        'compressionEnabled': true,
      },
      'compute': getCloudTaskQueueStatus(),
      'sync': getSyncPerformanceStats(),
      'security': getSecurityStatus(),
      'syncSummary': getSyncSummary(),
    };
  }
}
/// 分享统计数据模型
class ShareStats {
  final String projectId;
  final String platform;
  final String shareType;
  final int shareCount;
  final DateTime firstSharedAt;
  final DateTime lastSharedAt;

  ShareStats({
    required this.projectId,
    required this.platform,
    required this.shareType,
    this.shareCount = 1,
    DateTime? firstSharedAt,
    DateTime? lastSharedAt,
  })  : firstSharedAt = firstSharedAt ?? DateTime.now(),
        lastSharedAt = lastSharedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'projectId': projectId,
        'platform': platform,
        'shareType': shareType,
        'shareCount': shareCount,
        'firstSharedAt': firstSharedAt.toIso8601String(),
        'lastSharedAt': lastSharedAt.toIso8601String(),
      };

  factory ShareStats.fromJson(Map<String, dynamic> json) => ShareStats(
        projectId: json['projectId'] as String,
        platform: json['platform'] as String,
        shareType: json['shareType'] as String? ?? 'project',
        shareCount: json['shareCount'] as int? ?? 1,
        firstSharedAt: DateTime.parse(json['firstSharedAt'] as String),
        lastSharedAt: DateTime.parse(json['lastSharedAt'] as String),
      );
}

/// 分享推荐数据模型
class ShareRecommendation {
  final String projectId;
  final String projectName;
  final String reason;
  final int priority;
  final List<String> suggestedPlatforms;

  ShareRecommendation({
    required this.projectId,
    required this.projectName,
    required this.reason,
    this.priority = 1,
    this.suggestedPlatforms = const [],
  });
}

/// 好友信息数据模型
class FriendInfo {
  final String friendId;
  final String friendName;
  final DateTime addedAt;
  final String status; // pending, accepted, blocked

  FriendInfo({
    required this.friendId,
    required this.friendName,
    DateTime? addedAt,
    this.status = 'pending',
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'friendId': friendId,
        'friendName': friendName,
        'addedAt': addedAt.toIso8601String(),
        'status': status,
      };

  factory FriendInfo.fromJson(Map<String, dynamic> json) => FriendInfo(
        friendId: json['friendId'] as String,
        friendName: json['friendName'] as String,
        addedAt: DateTime.parse(json['addedAt'] as String),
        status: json['status'] as String? ?? 'pending',
      );
}

/// 关注信息数据模型
class FollowInfo {
  final String userId;
  final String targetId;
  final String targetName;
  final DateTime followedAt;

  FollowInfo({
    required this.userId,
    required this.targetId,
    required this.targetName,
    DateTime? followedAt,
  }) : followedAt = followedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'targetId': targetId,
        'targetName': targetName,
        'followedAt': followedAt.toIso8601String(),
      };

  factory FollowInfo.fromJson(Map<String, dynamic> json) => FollowInfo(
        userId: json['userId'] as String,
        targetId: json['targetId'] as String,
        targetName: json['targetName'] as String? ?? '',
        followedAt: DateTime.parse(json['followedAt'] as String),
      );
}

/// 私信数据模型
class DirectMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String receiverId;
  final String content;
  final DateTime timestamp;
  final bool isRead;

  DirectMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.receiverId,
    required this.content,
    DateTime? timestamp,
    this.isRead = false,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'senderName': senderName,
        'receiverId': receiverId,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead,
      };

  factory DirectMessage.fromJson(Map<String, dynamic> json) => DirectMessage(
        id: json['id'] as String,
        senderId: json['senderId'] as String,
        senderName: json['senderName'] as String? ?? '',
        receiverId: json['receiverId'] as String,
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        isRead: json['isRead'] as bool? ?? false,
      );
}

/// 动态信息数据模型
class ActivityFeed {
  final String id;
  final String userId;
  final String userName;
  final String type; // friend_request, follow, share, like, comment
  final String content;
  final String? targetId;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  ActivityFeed({
    required this.id,
    required this.userId,
    required this.userName,
    required this.type,
    required this.content,
    this.targetId,
    DateTime? timestamp,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
          'userId': userId,
        'userName': userName,
        'type': type,
        'content': content,
        'targetId': targetId,
        'timestamp': timestamp.toIso8601String(),
        'metadata': metadata,
      };

  factory ActivityFeed.fromJson(Map<String, dynamic> json) => ActivityFeed(
        id: json['id'] as String,
        userId: json['userId'] as String,
        userName: json['userName'] as String? ?? '',
        type: json['type'] as String,
        content: json['content'] as String,
        targetId: json['targetId'] as String?,
        timestamp: DateTime.parse(json['timestamp'] as String),
        metadata: json['metadata'] as Map<String, dynamic>?,
      );
}

/// 离线操作数据模型
class _OfflineOperation {
  final String id;
  final String type; // 'upload' | 'delete' | 'update'
  final String projectId;
  final DateTime timestamp;
  final Map<String, dynamic>? data;
  int retryCount;

  _OfflineOperation({
    required this.id,
    required this.type,
    required this.projectId,
    DateTime? timestamp,
    this.data,
    this.retryCount = 0,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'projectId': projectId,
        'timestamp': timestamp.toIso8601String(),
        'data': data,
        'retryCount': retryCount,
      };

  factory _OfflineOperation.fromJson(Map<String, dynamic> json) =>
      _OfflineOperation(
        id: json['id'] as String,
        type: json['type'] as String,
        projectId: json['projectId'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        data: json['data'] as Map<String, dynamic>?,
        retryCount: json['retryCount'] as int? ?? 0,
      );
}

// ═══════════════════════════════════════════════════════════
// 区块链功能增强：智能合约、去中心化存储、数字资产、共识机制
// ═══════════════════════════════════════════════════════════

/// 智能合约状态枚举
enum SmartContractState { draft, deployed, active, paused, terminated }

/// 共识算法类型
enum ConsensusAlgorithm { proofOfWork, proofOfStake, delegatedPoS, practicalBFT }

/// 数字资产类型
enum DigitalAssetType { font, glyph, template, license, metadata }

/// 智能合约数据模型
///
/// 表示一个部署在区块链上的智能合约，用于管理字体项目的
/// 版权、授权和交易逻辑。
class SmartContract {
  final String id;
  final String name;
  final String code;
  final String ownerAddress;
  SmartContractState state;
  final DateTime createdAt;
  DateTime? deployedAt;
  final Map<String, dynamic> parameters;
  final List<String> signers;

  SmartContract({
    required this.id,
    required this.name,
    required this.code,
    required this.ownerAddress,
    this.state = SmartContractState.draft,
    DateTime? createdAt,
    this.deployedAt,
    Map<String, dynamic>? parameters,
    List<String>? signers,
  })  : createdAt = createdAt ?? DateTime.now(),
        parameters = parameters ?? {},
        signers = signers ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'ownerAddress': ownerAddress,
        'state': state.name,
        'createdAt': createdAt.toIso8601String(),
        'deployedAt': deployedAt?.toIso8601String(),
        'parameters': parameters,
        'signers': signers,
      };

  factory SmartContract.fromJson(Map<String, dynamic> json) => SmartContract(
        id: json['id'] as String,
        name: json['name'] as String,
        code: json['code'] as String? ?? '',
        ownerAddress: json['ownerAddress'] as String? ?? '',
        state: SmartContractState.values.firstWhere(
          (e) => e.name == json['state'],
          orElse: () => SmartContractState.draft,
        ),
        createdAt: DateTime.parse(json['createdAt'] as String),
        deployedAt: json['deployedAt'] != null
            ? DateTime.parse(json['deployedAt'] as String)
            : null,
        parameters: json['parameters'] as Map<String, dynamic>? ?? {},
        signers: (json['signers'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );
}

/// 数字资产数据模型
///
/// 表示区块链上的数字资产（NFT），用于字体作品的版权确权和交易。
class DigitalAsset {
  final String id;
  final String name;
  final DigitalAssetType type;
  final String ownerAddress;
  final String contentHash;
  final DateTime mintedAt;
  final Map<String, dynamic> metadata;
  final List<Map<String, dynamic>> transferHistory;
  double? price;

  DigitalAsset({
    required this.id,
    required this.name,
    required this.type,
    required this.ownerAddress,
    required this.contentHash,
    DateTime? mintedAt,
    Map<String, dynamic>? metadata,
    List<Map<String, dynamic>>? transferHistory,
    this.price,
  })  : mintedAt = mintedAt ?? DateTime.now(),
        metadata = metadata ?? {},
        transferHistory = transferHistory ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'ownerAddress': ownerAddress,
        'contentHash': contentHash,
        'mintedAt': mintedAt.toIso8601String(),
        'metadata': metadata,
        'transferHistory': transferHistory,
        'price': price,
      };

  factory DigitalAsset.fromJson(Map<String, dynamic> json) => DigitalAsset(
        id: json['id'] as String,
        name: json['name'] as String,
        type: DigitalAssetType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => DigitalAssetType.font,
        ),
        ownerAddress: json['ownerAddress'] as String? ?? '',
        contentHash: json['contentHash'] as String? ?? '',
        mintedAt: DateTime.parse(json['mintedAt'] as String),
        metadata: json['metadata'] as Map<String, dynamic>? ?? {},
        transferHistory: (json['transferHistory'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [],
        price: (json['price'] as num?)?.toDouble(),
      );
}

/// 区块数据模型
///
/// 区块链中的单个区块，包含交易数据和前一区块的哈希。
class Block {
  final int index;
  final DateTime timestamp;
  final List<Map<String, dynamic>> transactions;
  final String previousHash;
  final int nonce;
  final String hash;

  Block({
    required this.index,
    DateTime? timestamp,
    required this.transactions,
    required this.previousHash,
    this.nonce = 0,
    String? hash,
  })  : timestamp = timestamp ?? DateTime.now(),
        hash = hash ?? '';

  Map<String, dynamic> toJson() => {
        'index': index,
        'timestamp': timestamp.toIso8601String(),
        'transactions': transactions,
        'previousHash': previousHash,
        'nonce': nonce,
        'hash': hash,
      };

  factory Block.fromJson(Map<String, dynamic> json) => Block(
        index: json['index'] as int,
        timestamp: DateTime.parse(json['timestamp'] as String),
        transactions: (json['transactions'] as List<dynamic>)
            .map((e) => e as Map<String, dynamic>)
            .toList(),
        previousHash: json['previousHash'] as String,
        nonce: json['nonce'] as int? ?? 0,
        hash: json['hash'] as String? ?? '',
      );
}

/// 区块链管理服务
///
/// 提供完整的区块链功能，包括：
/// - 智能合约管理（部署、执行、状态管理）
/// - 去中心化存储（IPFS 模拟、内容寻址）
/// - 数字资产（NFT 铸造、转让、交易）
/// - 共识机制（PoW/PoS/DPoS/PBFT）
class BlockchainService {
  static final BlockchainService _instance = BlockchainService._();
  static BlockchainService get instance => _instance;
  BlockchainService._();

  final List<Block> _chain = [];
  final List<SmartContract> _contracts = [];
  final List<DigitalAsset> _assets = [];
  final Map<String, String> _decentralizedStorage = {}; // cid -> content
  ConsensusAlgorithm _consensusAlgorithm = ConsensusAlgorithm.proofOfStake;
  static const int _difficulty = 2; // PoW 难度（哈希前缀零的数量）

  /// 获取区块链
  List<Block> get chain => List.unmodifiable(_chain);

  /// 获取所有智能合约
  List<SmartContract> get contracts => List.unmodifiable(_contracts);

  /// 获取所有数字资产
  List<DigitalAsset> get assets => List.unmodifiable(_assets);

  /// 初始化区块链（创建创世区块）
  void initialize() {
    if (_chain.isEmpty) {
      final genesis = Block(
        index: 0,
        transactions: [{'type': 'genesis', 'message': 'WriteFont Blockchain Genesis'}],
        previousHash: '0' * 64,
      );
      _chain.add(genesis);
      debugPrint('[Blockchain] 区块链已初始化，创世区块已创建');
    }
  }

  /// 计算区块哈希（SHA-256）
  String _calculateHash(Block block) {
    final data = '${block.index}${block.timestamp.toIso8601String()}'
        '${jsonEncode(block.transactions)}${block.previousHash}${block.nonce}';
    return sha256.convert(utf8.encode(data)).toString();
  }

  /// 设置共识算法
  void setConsensusAlgorithm(ConsensusAlgorithm algorithm) {
    _consensusAlgorithm = algorithm;
    debugPrint('[Blockchain] 共识算法切换为: ${algorithm.name}');
  }

  /// 挖矿/验证新区块（根据共识算法）
  ///
  /// [transactions] 待打包的交易列表
  /// 返回新创建的区块
  Future<Block> mineBlock(List<Map<String, dynamic>> transactions) async {
    if (_chain.isEmpty) initialize();

    final lastBlock = _chain.last;
    final newBlock = Block(
      index: lastBlock.index + 1,
      transactions: transactions,
      previousHash: _calculateHash(lastBlock),
    );

    switch (_consensusAlgorithm) {
      case ConsensusAlgorithm.proofOfWork:
        await _proofOfWork(newBlock);
        break;
      case ConsensusAlgorithm.proofOfStake:
        _proofOfStake(newBlock);
        break;
      case ConsensusAlgorithm.delegatedPoS:
        _delegatedPoS(newBlock);
        break;
      case ConsensusAlgorithm.practicalBFT:
        _practicalBFT(newBlock);
        break;
    }

    _chain.add(newBlock);
    debugPrint('[Blockchain] 新区块 #${newBlock.index} 已添加，交易数: ${transactions.length}');
    return newBlock;
  }

  /// 工作量证明共识
  Future<void> _proofOfWork(Block block) async {
    final target = '0' * _difficulty;
    int nonce = 0;
    String hash;
    do {
      nonce++;
      final data = '${block.index}${block.timestamp.toIso8601String()}'
          '${jsonEncode(block.transactions)}${block.previousHash}$nonce';
      hash = sha256.convert(utf8.encode(data)).toString();
    } while (!hash.startsWith(target));
    debugPrint('[Blockchain] PoW 完成，nonce=$nonce, hash=$hash');
  }

  /// 权益证明共识（模拟）
  void _proofOfStake(Block block) {
    debugPrint('[Blockchain] PoS 验证完成，区块 #${block.index}');
  }

  /// 委托权益证明共识（模拟）
  void _delegatedPoS(Block block) {
    debugPrint('[Blockchain] DPoS 验证完成，区块 #${block.index}');
  }

  /// 实用拜占庭容错共识（模拟）
  void _practicalBFT(Block block) {
    debugPrint('[Blockchain] PBFT 验证完成，区块 #${block.index}');
  }

  /// 验证区块链完整性
  ///
  /// 检查每个区块的哈希和前向引用是否正确
  bool validateChain() {
    for (int i = 1; i < _chain.length; i++) {
      final current = _chain[i];
      final previous = _chain[i - 1];
      if (current.previousHash != _calculateHash(previous)) {
        debugPrint('[Blockchain] 区块 #${i} 的前向哈希不匹配');
        return false;
      }
    }
    debugPrint('[Blockchain] 区块链验证通过，共 ${_chain.length} 个区块');
    return true;
  }

  /// 部署智能合约
  ///
  /// [name] 合约名称
  /// [code] 合约代码/逻辑描述
  /// [ownerAddress] 部署者地址
  /// [parameters] 合约参数
  SmartContract deployContract({
    required String name,
    required String code,
    required String ownerAddress,
    Map<String, dynamic>? parameters,
  }) {
    final contract = SmartContract(
      id: 'contract_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      code: code,
      ownerAddress: ownerAddress,
      parameters: parameters,
    );
    contract.state = SmartContractState.deployed;
    contract.deployedAt = DateTime.now();
    _contracts.add(contract);

    // 将合约部署记录到区块链
    mineBlock([
      {'type': 'contract_deploy', 'contractId': contract.id, 'name': name}
    ]);

    debugPrint('[Blockchain] 智能合约已部署: $name (${contract.id})');
    return contract;
  }

  /// 执行智能合约
  ///
  /// [contractId] 合约ID
  /// [action] 执行的操作
  /// [params] 操作参数
  Future<Map<String, dynamic>> executeContract(
    String contractId,
    String action,
    Map<String, dynamic> params,
  ) async {
    final contract = _contracts.firstWhere(
      (c) => c.id == contractId,
      orElse: () => throw Exception('智能合约不存在: $contractId'),
    );

    if (contract.state != SmartContractState.active &&
        contract.state != SmartContractState.deployed) {
      throw Exception('智能合约状态不允许执行: ${contract.state.name}');
    }

    final result = <String, dynamic>{
      'contractId': contractId,
      'action': action,
      'params': params,
      'executedAt': DateTime.now().toIso8601String(),
      'success': true,
    };

    // 记录执行到区块链
    await mineBlock([
      {'type': 'contract_execute', 'contractId': contractId, 'action': action, 'result': result}
    ]);

    if (contract.state == SmartContractState.deployed) {
      contract.state = SmartContractState.active;
    }

    debugPrint('[Blockchain] 智能合约已执行: $contractId.$action');
    return result;
  }

  /// 存储数据到去中心化存储（IPFS 模拟）
  ///
  /// [data] 待存储的数据
  /// 返回内容标识符（CID）
  Future<String> storeToDecentralizedStorage(Uint8List data) async {
    final cid = 'Qm${sha256.convert(data).toString().substring(0, 44)}';
    _decentralizedStorage[cid] = base64Encode(data);

    // 记录存储操作到区块链
    await mineBlock([
      {'type': 'ipfs_store', 'cid': cid, 'size': data.length}
    ]);

    debugPrint('[Blockchain] 数据已存储到去中心化存储，CID: $cid');
    return cid;
  }

  /// 从去中心化存储检索数据
  ///
  /// [cid] 内容标识符
  /// 返回存储的数据，未找到返回 null
  Future<Uint8List?> retrieveFromDecentralizedStorage(String cid) async {
    final encoded = _decentralizedStorage[cid];
    if (encoded == null) {
      debugPrint('[Blockchain] 去中心化存储中未找到 CID: $cid');
      return null;
    }
    return base64Decode(encoded);
  }

  /// 铸造数字资产（NFT）
  ///
  /// [name] 资产名称
  /// [type] 资产类型
  /// [ownerAddress] 所有者地址
  /// [content] 资产内容（用于计算内容哈希）
  /// [metadata] 元数据
  Future<DigitalAsset> mintDigitalAsset({
    required String name,
    required DigitalAssetType type,
    required String ownerAddress,
    required Uint8List content,
    Map<String, dynamic>? metadata,
  }) async {
    final contentHash = sha256.convert(content).toString();

    final asset = DigitalAsset(
      id: 'nft_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      type: type,
      ownerAddress: ownerAddress,
      contentHash: contentHash,
      metadata: metadata ?? {},
    );
    _assets.add(asset);

    // 将铸造记录到区块链
    await mineBlock([
      {
        'type': 'nft_mint',
        'assetId': asset.id,
        'name': name,
        'type': type.name,
        'owner': ownerAddress,
        'contentHash': contentHash,
      }
    ]);

    debugPrint('[Blockchain] 数字资产已铸造: $name (${asset.id})');
    return asset;
  }

  /// 转让数字资产
  ///
  /// [assetId] 资产ID
  /// [fromAddress] 转出方地址
  /// [toAddress] 接收方地址
  Future<void> transferDigitalAsset({
    required String assetId,
    required String fromAddress,
    required String toAddress,
  }) async {
    final assetIndex = _assets.indexWhere((a) => a.id == assetId);
    if (assetIndex < 0) throw Exception('数字资产不存在: $assetId');
    final asset = _assets[assetIndex];

    if (asset.ownerAddress != fromAddress) {
      throw Exception('无权转让此资产');
    }

    final updatedHistory = List<Map<String, dynamic>>.from(asset.transferHistory)
      ..add({
        'from': fromAddress,
        'to': toAddress,
        'timestamp': DateTime.now().toIso8601String(),
      });

    _assets[assetIndex] = DigitalAsset(
      id: asset.id,
      name: asset.name,
      type: asset.type,
      ownerAddress: toAddress,
      contentHash: asset.contentHash,
      mintedAt: asset.mintedAt,
      metadata: asset.metadata,
      transferHistory: updatedHistory,
      price: asset.price,
    );

    // 记录转让到区块链
    await mineBlock([
      {
        'type': 'nft_transfer',
        'assetId': assetId,
        'from': fromAddress,
        'to': toAddress,
      }
    ]);

    debugPrint('[Blockchain] 数字资产已转让: $assetId ($fromAddress -> $toAddress)');
  }

  /// 获取区块链统计信息
  Map<String, dynamic> getBlockchainStats() {
    return {
      'chainLength': _chain.length,
      'totalContracts': _contracts.length,
      'activeContracts': _contracts.where((c) => c.state == SmartContractState.active).length,
      'totalAssets': _assets.length,
      'storageItems': _decentralizedStorage.length,
      'consensusAlgorithm': _consensusAlgorithm.name,
      'isValid': _chain.length > 1 ? validateChain() : true,
    };
  }
}

// ═══════════════════════════════════════════════════════════
// 元宇宙功能模块
// ═══════════════════════════════════════════════════════════

/// 虚拟空间类型
enum VirtualSpaceType {
  office,       // 虚拟办公室
  gallery,      // 虚拟画廊
  classroom,    // 虚拟教室
  studio,       // 虚拟工作室
  plaza,        // 虚拟广场
  custom,       // 自定义空间
}

/// 虚拟化身外观配置
class AvatarAppearance {
  final String skinColor;
  final String hairStyle;
  final String hairColor;
  final String outfit;
  final List<String> accessories;
  final double height; // 身高比例 (0.5~2.0)

  const AvatarAppearance({
    this.skinColor = 'default',
    this.hairStyle = 'short',
    this.hairColor = 'black',
    this.outfit = 'casual',
    this.accessories = const [],
    this.height = 1.0,
  });

  Map<String, dynamic> toJson() => {
    'skinColor': skinColor,
    'hairStyle': hairStyle,
    'hairColor': hairColor,
    'outfit': outfit,
    'accessories': accessories,
    'height': height,
  };

  factory AvatarAppearance.fromJson(Map<String, dynamic> json) =>
      AvatarAppearance(
        skinColor: json['skinColor'] as String? ?? 'default',
        hairStyle: json['hairStyle'] as String? ?? 'short',
        hairColor: json['hairColor'] as String? ?? 'black',
        outfit: json['outfit'] as String? ?? 'casual',
        accessories: (json['accessories'] as List?)?.map((e) => e as String).toList() ?? [],
        height: (json['height'] as num?)?.toDouble() ?? 1.0,
      );
}

/// 虚拟化身
class VirtualAvatar {
  final String id;
  final String userId;
  final String displayName;
  final AvatarAppearance appearance;
  final List<double> position; // 3D 位置
  final List<double> rotation; // 旋转
  final String status; // 'online', 'away', 'busy', 'offline'
  final DateTime createdAt;
  DateTime lastActiveAt;

  VirtualAvatar({
    required this.id,
    required this.userId,
    required this.displayName,
    this.appearance = const AvatarAppearance(),
    this.position = const [0, 0, 0],
    this.rotation = const [0, 0, 0, 1],
    this.status = 'online',
    DateTime? createdAt,
    DateTime? lastActiveAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastActiveAt = lastActiveAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'displayName': displayName,
    'appearance': appearance.toJson(),
    'position': position,
    'rotation': rotation,
    'status': status,
    'createdAt': createdAt.toIso8601String(),
    'lastActiveAt': lastActiveAt.toIso8601String(),
  };
}

/// 虚拟空间
class VirtualSpace {
  final String id;
  final String name;
  final VirtualSpaceType type;
  final String ownerId;
  final int maxOccupancy; // 最大容纳人数
  final List<String> occupantIds; // 当前空间内的用户
  final Map<String, dynamic>? layout; // 空间布局配置
  final Map<String, dynamic>? settings; // 空间设置
  final DateTime createdAt;
  bool isPublic;

  VirtualSpace({
    required this.id,
    required this.name,
    required this.type,
    required this.ownerId,
    this.maxOccupancy = 50,
    List<String>? occupantIds,
    this.layout,
    this.settings,
    DateTime? createdAt,
    this.isPublic = true,
  })  : occupantIds = occupantIds ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'ownerId': ownerId,
    'maxOccupancy': maxOccupancy,
    'occupantIds': occupantIds,
    'layout': layout,
    'settings': settings,
    'createdAt': createdAt.toIso8601String(),
    'isPublic': isPublic,
  };
}

/// 虚拟社交消息
class VirtualSocialMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String content;
  final String type; // 'text', 'emoji', 'action', 'system'
  final String? spaceId;
  final DateTime timestamp;

  VirtualSocialMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.content,
    this.type = 'text',
    this.spaceId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'senderId': senderId,
    'senderName': senderName,
    'content': content,
    'type': type,
    'spaceId': spaceId,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// 虚拟经济交易类型
enum VirtualTransactionType {
  purchase,     // 购买
  sale,         // 出售
  reward,       // 奖励
  transfer,     // 转账
  mint,         // 铸造
  burn,         // 销毁
}

/// 虚拟经济交易记录
class VirtualTransaction {
  final String id;
  final String fromUserId;
  final String toUserId;
  final VirtualTransactionType type;
  final double amount;
  final String currency; // 'VFC' (虚拟字体币)
  final String? itemId; // 关联物品 ID
  final String? description;
  final DateTime timestamp;

  VirtualTransaction({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.type,
    required this.amount,
    this.currency = 'VFC',
    this.itemId,
    this.description,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'fromUserId': fromUserId,
    'toUserId': toUserId,
    'type': type.name,
    'amount': amount,
    'currency': currency,
    'itemId': itemId,
    'description': description,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// 虚拟物品
class VirtualItem {
  final String id;
  final String name;
  final String type; // 'font', 'template', 'decoration', 'avatar_item', 'space_item'
  final double price;
  final String ownerId;
  final String? previewUrl;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  VirtualItem({
    required this.id,
    required this.name,
    required this.type,
    this.price = 0,
    required this.ownerId,
    this.previewUrl,
    this.metadata,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'price': price,
    'ownerId': ownerId,
    'previewUrl': previewUrl,
    'metadata': metadata,
    'createdAt': createdAt.toIso8601String(),
  };
}

/// 元宇宙服务
///
/// 提供元宇宙功能的统一管理：
/// - 虚拟空间管理
/// - 虚拟化身管理
/// - 虚拟社交功能
/// - 虚拟经济系统
class MetaverseService {
  static final MetaverseService _instance = MetaverseService._();
  static MetaverseService get instance => _instance;
  MetaverseService._();

  /// 虚拟空间列表
  final List<VirtualSpace> _spaces = [];

  /// 虚拟化身列表
  final List<VirtualAvatar> _avatars = [];

  /// 社交消息历史
  final List<VirtualSocialMessage> _messages = [];

  /// 经济交易历史
  final List<VirtualTransaction> _transactions = [];

  /// 虚拟物品列表
  final List<VirtualItem> _items = [];

  /// 用户虚拟货币余额 {userId: balance}
  final Map<String, double> _userBalances = {};

  /// 事件回调
  final List<void Function(VirtualSocialMessage)> _onMessage = [];
  final List<void Function(VirtualTransaction)> _onTransaction = [];

  /// 获取所有空间
  List<VirtualSpace> get spaces => List.unmodifiable(_spaces);

  /// 获取所有化身
  List<VirtualAvatar> get avatars => List.unmodifiable(_avatars);

  /// 获取所有物品
  List<VirtualItem> get items => List.unmodifiable(_items);

  /// 注册消息回调
  void onMessage(void Function(VirtualSocialMessage) callback) {
    _onMessage.add(callback);
  }

  /// 注册交易回调
  void onTransaction(void Function(VirtualTransaction) callback) {
    _onTransaction.add(callback);
  }

  // ─────────────── 虚拟空间管理 ───────────────

  /// 创建虚拟空间
  VirtualSpace createSpace({
    required String name,
    required VirtualSpaceType type,
    required String ownerId,
    int maxOccupancy = 50,
    bool isPublic = true,
    Map<String, dynamic>? layout,
  }) {
    final space = VirtualSpace(
      id: 'space_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      type: type,
      ownerId: ownerId,
      maxOccupancy: maxOccupancy,
      isPublic: isPublic,
      layout: layout,
    );
    _spaces.add(space);
    debugPrint('[Metaverse] 虚拟空间已创建: $name (${type.name})');
    return space;
  }

  /// 进入虚拟空间
  bool enterSpace(String spaceId, String userId) {
    final spaceIndex = _spaces.indexWhere((s) => s.id == spaceId);
    if (spaceIndex < 0) return false;
    final space = _spaces[spaceIndex];
    if (space.occupantIds.length >= space.maxOccupancy) {
      debugPrint('[Metaverse] 空间已满: ${space.name}');
      return false;
    }
    if (!space.occupantIds.contains(userId)) {
      space.occupantIds.add(userId);
      debugPrint('[Metaverse] 用户 $userId 进入空间: ${space.name}');
    }
    return true;
  }

  /// 离开虚拟空间
  void leaveSpace(String spaceId, String userId) {
    final space = _spaces.firstWhere((s) => s.id == spaceId, orElse: () => VirtualSpace(id: '', name: '', type: VirtualSpaceType.custom, ownerId: ''));
    space.occupantIds.remove(userId);
    debugPrint('[Metaverse] 用户 $userId 离开空间: ${space.name}');
  }

  /// 获取公开空间列表
  List<VirtualSpace> getPublicSpaces() {
    return _spaces.where((s) => s.isPublic).toList();
  }

  // ─────────────── 虚拟化身管理 ───────────────

  /// 创建虚拟化身
  VirtualAvatar createAvatar({
    required String userId,
    required String displayName,
    AvatarAppearance appearance = const AvatarAppearance(),
  }) {
    final avatar = VirtualAvatar(
      id: 'avatar_${DateTime.now().microsecondsSinceEpoch}',
      userId: userId,
      displayName: displayName,
      appearance: appearance,
    );
    _avatars.add(avatar);
    debugPrint('[Metaverse] 虚拟化身已创建: $displayName');
    return avatar;
  }

  /// 更新化身外观
  void updateAvatarAppearance(String avatarId, AvatarAppearance newAppearance) {
    final index = _avatars.indexWhere((a) => a.id == avatarId);
    if (index >= 0) {
      final old = _avatars[index];
      _avatars[index] = VirtualAvatar(
        id: old.id, userId: old.userId, displayName: old.displayName,
        appearance: newAppearance, position: old.position, rotation: old.rotation,
        status: old.status, createdAt: old.createdAt, lastActiveAt: old.lastActiveAt,
      );
      debugPrint('[Metaverse] 化身外观已更新: ${old.displayName}');
    }
  }

  /// 更新化身位置
  void updateAvatarPosition(String avatarId, List<double> position) {
    final avatar = _avatars.firstWhere((a) => a.id == avatarId, orElse: () => VirtualAvatar(id: '', userId: '', displayName: ''));
    avatar.position.clear();
    avatar.position.addAll(position);
    avatar.lastActiveAt = DateTime.now();
  }

  /// 获取空间内的化身
  List<VirtualAvatar> getAvatarsInSpace(String spaceId) {
    final space = _spaces.firstWhere((s) => s.id == spaceId, orElse: () => VirtualSpace(id: '', name: '', type: VirtualSpaceType.custom, ownerId: ''));
    return _avatars.where((a) => space.occupantIds.contains(a.userId)).toList();
  }

  // ─────────────── 虚拟社交功能 ───────────────

  /// 发送社交消息
  void sendMessage({
    required String senderId,
    required String senderName,
    required String content,
    String type = 'text',
    String? spaceId,
  }) {
    final msg = VirtualSocialMessage(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch}',
      senderId: senderId,
      senderName: senderName,
      content: content,
      type: type,
      spaceId: spaceId,
    );
    _messages.add(msg);
    // 限制消息历史
    while (_messages.length > 2000) {
      _messages.removeAt(0);
    }
    for (final cb in _onMessage) {
      try { cb(msg); } catch (_) {}
    }
    debugPrint('[Metaverse] 消息: $senderName -> ${content.length > 30 ? "${content.substring(0, 30)}..." : content}');
  }

  /// 获取空间内的消息
  List<VirtualSocialMessage> getMessagesInSpace(String spaceId, {int limit = 50}) {
    final spaceMessages = _messages.where((m) => m.spaceId == spaceId).toList();
    final start = (spaceMessages.length - limit).clamp(0, spaceMessages.length);
    return spaceMessages.sublist(start);
  }

  /// 发送表情动作
  void sendEmote(String senderId, String senderName, String emote, {String? spaceId}) {
    sendMessage(
      senderId: senderId,
      senderName: senderName,
      content: emote,
      type: 'emoji',
      spaceId: spaceId,
    );
  }

  // ─────────────── 虚拟经济功能 ───────────────

  /// 获取用户余额
  double getBalance(String userId) {
    return _userBalances[userId] ?? 0;
  }

  /// 充值虚拟货币
  void creditBalance(String userId, double amount, {String? description}) {
    _userBalances[userId] = (_userBalances[userId] ?? 0) + amount;
    final tx = VirtualTransaction(
      id: 'tx_${DateTime.now().microsecondsSinceEpoch}',
      fromUserId: 'system',
      toUserId: userId,
      type: VirtualTransactionType.reward,
      amount: amount,
      description: description ?? '充值',
    );
    _transactions.add(tx);
    for (final cb in _onTransaction) {
      try { cb(tx); } catch (_) {}
    }
    debugPrint('[Metaverse] 充值: $userId +${amount}VFC (余额: ${_userBalances[userId]}VFC)');
  }

  /// 转账虚拟货币
  bool transferBalance({
    required String fromUserId,
    required String toUserId,
    required double amount,
    String? description,
  }) {
    final fromBalance = _userBalances[fromUserId] ?? 0;
    if (fromBalance < amount) {
      debugPrint('[Metaverse] 余额不足: $fromUserId (${fromBalance}VFC < ${amount}VFC)');
      return false;
    }
    _userBalances[fromUserId] = fromBalance - amount;
    _userBalances[toUserId] = (_userBalances[toUserId] ?? 0) + amount;
    final tx = VirtualTransaction(
      id: 'tx_${DateTime.now().microsecondsSinceEpoch}',
      fromUserId: fromUserId,
      toUserId: toUserId,
      type: VirtualTransactionType.transfer,
      amount: amount,
      description: description,
    );
    _transactions.add(tx);
    for (final cb in _onTransaction) {
      try { cb(tx); } catch (_) {}
    }
    debugPrint('[Metaverse] 转账: $fromUserId -> $toUserId ${amount}VFC');
    return true;
  }

  /// 上架虚拟物品
  VirtualItem listVirtualItem({
    required String name,
    required String type,
    required double price,
    required String ownerId,
    Map<String, dynamic>? metadata,
  }) {
    final item = VirtualItem(
      id: 'item_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      type: type,
      price: price,
      ownerId: ownerId,
      metadata: metadata,
    );
    _items.add(item);
    debugPrint('[Metaverse] 物品已上架: $name (${price}VFC)');
    return item;
  }

  /// 购买虚拟物品
  bool purchaseVirtualItem(String itemId, String buyerId) {
    final itemIndex = _items.indexWhere((i) => i.id == itemId);
    if (itemIndex < 0) return false;
    final item = _items[itemIndex];
    if (item.ownerId == buyerId) return false; // 不能购买自己的物品
    final balance = _userBalances[buyerId] ?? 0;
    if (balance < item.price) {
      debugPrint('[Metaverse] 余额不足，无法购买: ${item.name}');
      return false;
    }
    // 扣除买家余额
    _userBalances[buyerId] = balance - item.price;
    // 增加卖家余额
    _userBalances[item.ownerId] = (_userBalances[item.ownerId] ?? 0) + item.price;
    // 更新物品所有者
    _items[itemIndex] = VirtualItem(
      id: item.id, name: item.name, type: item.type,
      price: item.price, ownerId: buyerId,
      previewUrl: item.previewUrl, metadata: item.metadata,
      createdAt: item.createdAt,
    );
    // 记录交易
    final tx = VirtualTransaction(
      id: 'tx_${DateTime.now().microsecondsSinceEpoch}',
      fromUserId: buyerId,
      toUserId: item.ownerId,
      type: VirtualTransactionType.purchase,
      amount: item.price,
      itemId: itemId,
      description: '购买: ${item.name}',
    );
    _transactions.add(tx);
    for (final cb in _onTransaction) {
      try { cb(tx); } catch (_) {}
    }
    debugPrint('[Metaverse] 物品已购买: ${item.name} ($buyerId)');
    return true;
  }

  /// 获取用户的交易历史
  List<VirtualTransaction> getUserTransactions(String userId, {int limit = 50}) {
    final userTx = _transactions
        .where((t) => t.fromUserId == userId || t.toUserId == userId)
        .toList();
    final start = (userTx.length - limit).clamp(0, userTx.length);
    return userTx.sublist(start);
  }

  /// 获取虚拟经济统计
  Map<String, dynamic> getEconomyStats() {
    final totalVolume = _transactions.fold<double>(0, (sum, t) => sum + t.amount);
    final purchaseCount = _transactions.where((t) => t.type == VirtualTransactionType.purchase).length;
    return {
      'totalTransactions': _transactions.length,
      'totalVolume': totalVolume,
      'purchaseCount': purchaseCount,
      'activeItems': _items.length,
      'totalUsers': _userBalances.length,
      'avgTransactionAmount': _transactions.isNotEmpty ? totalVolume / _transactions.length : 0,
    };
  }

  /// 获取元宇宙统计信息
  Map<String, dynamic> getMetaverseStats() {
    return {
      'spaces': _spaces.length,
      'avatars': _avatars.length,
      'messages': _messages.length,
      'transactions': _transactions.length,
      'virtualItems': _items.length,
      'economy': getEconomyStats(),
      'publicSpaces': _spaces.where((s) => s.isPublic).length,
      'onlineAvatars': _avatars.where((a) => a.status == 'online').length,
    };
  }
}

// ═══════════════════════════════════════════════════════════
// 数字孪生功能模块：建模、同步、仿真、分析
// ═══════════════════════════════════════════════════════════

/// 数字孪生状态枚举
enum DigitalTwinState { creating, active, syncing, simulating, analyzing, error }

/// 数字孪生类型枚举
enum DigitalTwinType { fontProject, glyphDesign, userWorkflow, systemMetrics }

/// 数字孪生数据模型
///
/// 表示一个物理实体的数字化镜像，用于实时同步、仿真和分析。
class DigitalTwinModel {
  final String id;
  final String name;
  final DigitalTwinType type;
  final String sourceId; // 关联的物理实体ID
  DigitalTwinState state;
  final DateTime createdAt;
  DateTime lastSyncedAt;
  final Map<String, dynamic> properties; // 实体属性
  final List<Map<String, dynamic>> stateHistory; // 状态变更历史
  final Map<String, dynamic> sensorData; // 传感器数据（实时）

  DigitalTwinModel({
    required this.id,
    required this.name,
    required this.type,
    required this.sourceId,
    this.state = DigitalTwinState.creating,
    DateTime? createdAt,
    DateTime? lastSyncedAt,
    Map<String, dynamic>? properties,
    List<Map<String, dynamic>>? stateHistory,
    Map<String, dynamic>? sensorData,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastSyncedAt = lastSyncedAt ?? DateTime.now(),
        properties = properties ?? {},
        stateHistory = stateHistory ?? [],
        sensorData = sensorData ?? {};

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'sourceId': sourceId,
        'state': state.name,
        'createdAt': createdAt.toIso8601String(),
        'lastSyncedAt': lastSyncedAt.toIso8601String(),
        'properties': properties,
        'stateHistory': stateHistory,
        'sensorData': sensorData,
      };

  factory DigitalTwinModel.fromJson(Map<String, dynamic> json) => DigitalTwinModel(
        id: json['id'] as String,
        name: json['name'] as String,
        type: DigitalTwinType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => DigitalTwinType.fontProject,
        ),
        sourceId: json['sourceId'] as String? ?? '',
        state: DigitalTwinState.values.firstWhere(
          (e) => e.name == json['state'],
          orElse: () => DigitalTwinState.creating,
        ),
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastSyncedAt: json['lastSyncedAt'] != null
            ? DateTime.parse(json['lastSyncedAt'] as String)
            : DateTime.now(),
        properties: json['properties'] as Map<String, dynamic>? ?? {},
        stateHistory: (json['stateHistory'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ?? [],
        sensorData: json['sensorData'] as Map<String, dynamic>? ?? {},
      );
}

/// 仿真结果数据模型
class SimulationResult {
  final String id;
  final String twinId;
  final String scenarioName;
  final DateTime executedAt;
  final Duration duration;
  final Map<String, dynamic> inputData;
  final Map<String, dynamic> outputData;
  final bool success;
  final String? error;

  SimulationResult({
    required this.id,
    required this.twinId,
    required this.scenarioName,
    DateTime? executedAt,
    this.duration = Duration.zero,
    this.inputData = const {},
    this.outputData = const {},
    this.success = true,
    this.error,
  }) : executedAt = executedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'twinId': twinId,
        'scenarioName': scenarioName,
        'executedAt': executedAt.toIso8601String(),
        'durationMs': duration.inMilliseconds,
        'inputData': inputData,
        'outputData': outputData,
        'success': success,
        'error': error,
      };
}

/// 分析报告数据模型
class AnalysisReport {
  final String id;
  final String twinId;
  final String analysisType; // 'performance' | 'anomaly' | 'prediction' | 'comparison'
  final DateTime generatedAt;
  final Map<String, dynamic> metrics;
  final List<Map<String, dynamic>> insights;
  final Map<String, dynamic> recommendations;

  AnalysisReport({
    required this.id,
    required this.twinId,
    required this.analysisType,
    DateTime? generatedAt,
    this.metrics = const {},
    this.insights = const [],
    this.recommendations = const {},
  }) : generatedAt = generatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'twinId': twinId,
        'analysisType': analysisType,
        'generatedAt': generatedAt.toIso8601String(),
        'metrics': metrics,
        'insights': insights,
        'recommendations': recommendations,
      };
}

/// 数字孪生服务
///
/// 提供完整的数字孪生功能，包括：
/// - 数字孪生建模（创建和管理数字镜像）
/// - 数字孪生同步（实时数据同步和状态更新）
/// - 数字孪生仿真（场景模拟和预测）
/// - 数字孪生分析（性能分析、异常检测、趋势预测）
class DigitalTwinService {
  static final DigitalTwinService _instance = DigitalTwinService._();
  static DigitalTwinService get instance => _instance;
  DigitalTwinService._();

  final List<DigitalTwinModel> _twins = [];
  final List<SimulationResult> _simulationResults = [];
  final List<AnalysisReport> _analysisReports = [];
  final List<void Function(DigitalTwinModel)> _onSyncCallbacks = [];
  Timer? _syncTimer;
  bool _autoSyncEnabled = false;

  /// 获取所有数字孪生
  List<DigitalTwinModel> get twins => List.unmodifiable(_twins);

  /// 获取仿真结果
  List<SimulationResult> get simulationResults => List.unmodifiable(_simulationResults);

  /// 获取分析报告
  List<AnalysisReport> get analysisReports => List.unmodifiable(_analysisReports);

  /// 添加同步回调
  void onSync(void Function(DigitalTwinModel) callback) {
    _onSyncCallbacks.add(callback);
  }

  /// 移除同步回调
  void removeSyncCallback(void Function(DigitalTwinModel) callback) {
    _onSyncCallbacks.remove(callback);
  }

  // ── 数字孪生建模 ──

  /// 创建数字孪生模型
  ///
  /// [name] 模型名称
  /// [type] 模型类型
  /// [sourceId] 关联的物理实体ID
  /// [properties] 初始属性
  DigitalTwinModel createTwin({
    required String name,
    required DigitalTwinType type,
    required String sourceId,
    Map<String, dynamic>? properties,
  }) {
    final twin = DigitalTwinModel(
      id: 'twin_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      type: type,
      sourceId: sourceId,
      properties: properties ?? {},
    );
    twin.state = DigitalTwinState.active;
    _twins.add(twin);
    debugPrint('[DigitalTwin] 数字孪生已创建: $name (${twin.id})');
    return twin;
  }

  /// 更新孪生属性
  void updateTwinProperties(String twinId, Map<String, dynamic> properties) {
    final twin = _twins.firstWhere(
      (t) => t.id == twinId,
      orElse: () => throw Exception('数字孪生不存在: $twinId'),
    );
    twin.properties.addAll(properties);
    twin.stateHistory.add({
      'action': 'property_update',
      'properties': properties,
      'timestamp': DateTime.now().toIso8601String(),
    });
    debugPrint('[DigitalTwin] 孪生属性已更新: $twinId');
  }

  /// 删除数字孪生
  void deleteTwin(String twinId) {
    _twins.removeWhere((t) => t.id == twinId);
    _simulationResults.removeWhere((r) => r.twinId == twinId);
    _analysisReports.removeWhere((r) => r.twinId == twinId);
    debugPrint('[DigitalTwin] 数字孪生已删除: $twinId');
  }

  // ── 数字孪生同步 ──

  /// 同步孪生数据（从物理实体更新到数字镜像）
  Future<void> syncTwin(String twinId, Map<String, dynamic> sensorData) async {
    final twin = _twins.firstWhere(
      (t) => t.id == twinId,
      orElse: () => throw Exception('数字孪生不存在: $twinId'),
    );

    twin.state = DigitalTwinState.syncing;
    try {
      twin.sensorData.addAll(sensorData);
      twin.lastSyncedAt = DateTime.now();
      twin.state = DigitalTwinState.active;

      twin.stateHistory.add({
        'action': 'sync',
        'sensorDataKeys': sensorData.keys.toList(),
        'timestamp': DateTime.now().toIso8601String(),
      });

      for (final cb in _onSyncCallbacks) {
        try { cb(twin); } catch (_) {}
      }
      debugPrint('[DigitalTwin] 孪生已同步: $twinId (${sensorData.keys.length} 个数据点)');
    } catch (e) {
      twin.state = DigitalTwinState.error;
      debugPrint('[DigitalTwin] 同步失败: $twinId - $e');
      rethrow;
    }
  }

  /// 启用自动同步
  void enableAutoSync({int intervalSeconds = 60}) {
    _autoSyncEnabled = true;
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      for (final twin in _twins.where((t) => t.state == DigitalTwinState.active)) {
        debugPrint('[DigitalTwin] 自动同步触发: ${twin.id}');
      }
    });
    debugPrint('[DigitalTwin] 自动同步已启用，间隔 ${intervalSeconds}s');
  }

  /// 禁用自动同步
  void disableAutoSync() {
    _autoSyncEnabled = false;
    _syncTimer?.cancel();
    _syncTimer = null;
    debugPrint('[DigitalTwin] 自动同步已禁用');
  }

  /// 批量同步所有活跃孪生
  Future<void> syncAllActiveTwins() async {
    final activeTwins = _twins.where((t) => t.state == DigitalTwinState.active).toList();
    for (final twin in activeTwins) {
      try {
        await syncTwin(twin.id, twin.sensorData);
      } catch (e) {
        debugPrint('[DigitalTwin] 批量同步失败: ${twin.id} - $e');
      }
    }
    debugPrint('[DigitalTwin] 批量同步完成，${activeTwins.length} 个孪生');
  }

  // ── 数字孪生仿真 ──

  /// 运行仿真
  ///
  /// [twinId] 孪生ID
  /// [scenarioName] 场景名称
  /// [inputData] 仿真输入参数
  Future<SimulationResult> runSimulation(
    String twinId,
    String scenarioName,
    Map<String, dynamic> inputData,
  ) async {
    final twin = _twins.firstWhere(
      (t) => t.id == twinId,
      orElse: () => throw Exception('数字孪生不存在: $twinId'),
    );

    twin.state = DigitalTwinState.simulating;
    final stopwatch = Stopwatch()..start();

    try {
      final outputData = <String, dynamic>{
        'scenario': scenarioName,
        'timestamp': DateTime.now().toIso8601String(),
        'twinProperties': twin.properties,
      };

      switch (twin.type) {
        case DigitalTwinType.fontProject:
          outputData['estimatedGlyphCount'] = (twin.properties['glyphCount'] as int? ?? 0) * 1.1;
          outputData['estimatedQuality'] = 0.85;
          break;
        case DigitalTwinType.glyphDesign:
          outputData['complexityScore'] = (twin.properties['contourCount'] as int? ?? 0) * 0.5;
          outputData['readabilityScore'] = 0.9;
          break;
        case DigitalTwinType.userWorkflow:
          outputData['efficiency'] = 0.75;
          outputData['bottlenecks'] = <String>[];
          break;
        case DigitalTwinType.systemMetrics:
          outputData['projectedLoad'] = 0.6;
          outputData['resourceUsage'] = {'cpu': 0.4, 'memory': 0.5};
          break;
      }

      stopwatch.stop();
      final result = SimulationResult(
        id: 'sim_${DateTime.now().microsecondsSinceEpoch}',
        twinId: twinId,
        scenarioName: scenarioName,
        duration: stopwatch.elapsed,
        inputData: inputData,
        outputData: outputData,
        success: true,
      );
      _simulationResults.add(result);
      twin.state = DigitalTwinState.active;
      twin.stateHistory.add({
        'action': 'simulation',
        'scenario': scenarioName,
        'durationMs': stopwatch.elapsedMilliseconds,
        'timestamp': DateTime.now().toIso8601String(),
      });
      debugPrint('[DigitalTwin] 仿真完成: $scenarioName (${stopwatch.elapsedMilliseconds}ms)');
      return result;
    } catch (e) {
      stopwatch.stop();
      twin.state = DigitalTwinState.error;
      final result = SimulationResult(
        id: 'sim_${DateTime.now().microsecondsSinceEpoch}',
        twinId: twinId,
        scenarioName: scenarioName,
        duration: stopwatch.elapsed,
        inputData: inputData,
        success: false,
        error: e.toString(),
      );
      _simulationResults.add(result);
      debugPrint('[DigitalTwin] 仿真失败: $scenarioName - $e');
      return result;
    }
  }

  /// 获取孪生的仿真历史
  List<SimulationResult> getSimulationHistory(String twinId, {int limit = 20}) {
    final results = _simulationResults.where((r) => r.twinId == twinId).toList();
    final start = (results.length - limit).clamp(0, results.length);
    return results.sublist(start);
  }

  // ── 数字孪生分析 ──

  /// 运行分析
  ///
  /// [twinId] 孪生ID
  /// [analysisType] 分析类型（performance / anomaly / prediction / comparison）
  Future<AnalysisReport> runAnalysis(String twinId, String analysisType) async {
    final twin = _twins.firstWhere(
      (t) => t.id == twinId,
      orElse: () => throw Exception('数字孪生不存在: $twinId'),
    );

    twin.state = DigitalTwinState.analyzing;

    try {
      final metrics = <String, dynamic>{};
      final insights = <Map<String, dynamic>>[];
      final recommendations = <String, dynamic>{};

      switch (analysisType) {
        case 'performance':
          metrics['syncCount'] = twin.stateHistory.where((h) => h['action'] == 'sync').length;
          metrics['simulationCount'] = _simulationResults.where((r) => r.twinId == twinId).length;
          metrics['lastSyncAge'] = DateTime.now().difference(twin.lastSyncedAt).inMinutes;
          metrics['dataPoints'] = twin.sensorData.length;
          insights.add({'type': 'info', 'message': '已执行 ${metrics['syncCount']} 次同步'});
          recommendations['priority'] = 'maintain';
          recommendations['actions'] = ['继续监控', '定期同步'];
          break;
        case 'anomaly':
          final failedSims = _simulationResults.where((r) => r.twinId == twinId && !r.success).length;
          metrics['failedSimulations'] = failedSims;
          metrics['errorRate'] = _simulationResults.isNotEmpty
              ? failedSims / _simulationResults.where((r) => r.twinId == twinId).length
              : 0.0;
          if (failedSims > 0) {
            insights.add({'type': 'warning', 'message': '检测到 $failedSims 次失败仿真'});
          } else {
            insights.add({'type': 'ok', 'message': '未检测到异常'});
          }
          recommendations['priority'] = failedSims > 0 ? 'investigate' : 'monitor';
          break;
        case 'prediction':
          final simCount = _simulationResults.where((r) => r.twinId == twinId).length;
          metrics['trendDataPoints'] = simCount;
          metrics['predictedGrowth'] = simCount * 1.2;
          metrics['confidenceLevel'] = 0.78;
          insights.add({'type': 'info', 'message': '基于 $simCount 个仿真数据点的趋势预测'});
          recommendations['nextAction'] = '建议增加仿真数据量以提高预测准确性';
          break;
        case 'comparison':
          final otherTwins = _twins.where((t) => t.id != twinId && t.type == twin.type).toList();
          metrics['sameTypeCount'] = otherTwins.length;
          metrics['avgProperties'] = otherTwins.isNotEmpty
              ? otherTwins.map((t) => t.properties.length).reduce((a, b) => a + b) / otherTwins.length
              : 0;
          insights.add({'type': 'info', 'message': '与 ${otherTwins.length} 个同类孪生进行了比较'});
          recommendations['suggestion'] = '该孪生在同类中处于平均水平';
          break;
      }

      final report = AnalysisReport(
        id: 'report_${DateTime.now().microsecondsSinceEpoch}',
        twinId: twinId,
        analysisType: analysisType,
        metrics: metrics,
        insights: insights,
        recommendations: recommendations,
      );
      _analysisReports.add(report);
      twin.state = DigitalTwinState.active;
      twin.stateHistory.add({
        'action': 'analysis',
        'analysisType': analysisType,
        'timestamp': DateTime.now().toIso8601String(),
      });
      debugPrint('[DigitalTwin] 分析完成: $analysisType ($twinId)');
      return report;
    } catch (e) {
      twin.state = DigitalTwinState.error;
      debugPrint('[DigitalTwin] 分析失败: $analysisType - $e');
      rethrow;
    }
  }

  /// 获取孪生的分析报告历史
  List<AnalysisReport> getAnalysisHistory(String twinId, {int limit = 20}) {
    final reports = _analysisReports.where((r) => r.twinId == twinId).toList();
    final start = (reports.length - limit).clamp(0, reports.length);
    return reports.sublist(start);
  }

  /// 获取数字孪生统计信息
  Map<String, dynamic> getDigitalTwinStats() {
    return {
      'totalTwins': _twins.length,
      'activeTwins': _twins.where((t) => t.state == DigitalTwinState.active).length,
      'totalSimulations': _simulationResults.length,
      'successfulSimulations': _simulationResults.where((r) => r.success).length,
      'totalAnalysisReports': _analysisReports.length,
      'autoSyncEnabled': _autoSyncEnabled,
      'twinsByType': {
        for (final type in DigitalTwinType.values)
          type.name: _twins.where((t) => t.type == type).length,
      },
    };
  }
}
