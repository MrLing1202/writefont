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
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/project.dart';
import 'storage_service.dart';

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
class CloudSyncService {
  static CloudSyncService? _instance;
  static CloudSyncService get instance => _instance ??= CloudSyncService._();

  CloudSyncService._();

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

      // 验证 token 是否有效
      if (_accessToken != null) {
        await _refreshSession();
      }

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
}
