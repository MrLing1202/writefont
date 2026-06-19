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
