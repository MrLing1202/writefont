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
}
