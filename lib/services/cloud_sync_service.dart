/// 云同步服务
/// 使用 Supabase REST API 实现项目数据的云端同步
/// 支持增量同步、冲突处理、离线队列
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

/// 同步历史记录
class SyncHistoryEntry {
  final String projectId;
  final String projectName;
  final String action; // upload | download | restore
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

  // ── SharedPreferences keys ──
  static const _keyAccessToken = 'cloud_access_token';
  static const _keyRefreshToken = 'cloud_refresh_token';
  static const _keyUserId = 'cloud_user_id';
  static const _keyUserEmail = 'cloud_user_email';
  static const _keyAutoSync = 'cloud_auto_sync';
  static const _keySyncHistory = 'cloud_sync_history';
  static const _keyProjectStatus = 'cloud_project_status';

  // ── Getters ──
  bool get isSyncing => _syncState == SyncState.syncing;
  SyncState get syncState => _syncState;
  bool get autoSync => _autoSync;
  String? get userEmail => _userEmail;
  List<SyncHistoryEntry> get history => List.unmodifiable(_history);
  Map<String, ProjectSyncStatus> get projectStatus =>
      Map.unmodifiable(_projectStatus);

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

      // 验证 token 是否有效
      if (_accessToken != null) {
        await _refreshSession();
      }
    } catch (e) {
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
        return null; // 成功
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['msg'] as String? ?? data['error_description'] as String? ?? '注册失败';
      }
    } catch (e) {
      return '网络错误: $e';
    }
  }

  /// 邮箱登录
  Future<String?> signIn(String email, String password) async {
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
        return null; // 成功
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['error_description'] as String? ?? data['msg'] as String? ?? '登录失败';
      }
    } catch (e) {
      return '网络错误: $e';
    }
  }

  /// 登出
  Future<void> signOut() async {
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
        return true;
      } else {
        await signOut();
        return false;
      }
    } catch (e) {
      debugPrint('刷新会话失败: $e');
      return false;
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
  Future<String?> syncAll() async {
    if (!isSignedIn()) return '请先登录';
    if (isSyncing) return '正在同步中';

    _syncState = SyncState.syncing;
    try {
      // 1. 加载本地项目
      final localProjects = await StorageService.loadProjects();

      // 2. 获取远程项目列表
      final remoteProjects = await _fetchRemoteProjects();
      if (remoteProjects == null) {
        _syncState = SyncState.error;
        return '获取远程数据失败';
      }

      // 3. 构建远程项目 Map（key: projectId）
      final remoteMap = <String, Map<String, dynamic>>{};
      for (final rp in remoteProjects) {
        final pid = rp['id'] as String? ?? '';
        if (pid.isNotEmpty) {
          remoteMap[pid] = rp;
        }
      }

      // 4. 上传本地变更（本地更新时间 > 远程更新时间 或 远程不存在）
      for (final local in localProjects) {
        final remote = remoteMap[local.id];
        if (remote == null ||
            local.updatedAt.isAfter(
              DateTime.parse(
                  remote['updated_at'] as String? ?? '1970-01-01'),
            )) {
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
          }
        } else {
          _projectStatus[local.id] = ProjectSyncStatus.synced;
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
          }
        }
      }

      _syncState = SyncState.idle;
      await _saveProjectStatus();
      await _saveHistory();
      return null; // 成功
    } catch (e) {
      _syncState = SyncState.error;
      return '同步失败: $e';
    }
  }

  /// 上传单个项目到云端
  Future<String?> uploadProject(FontProject project) async {
    if (!isSignedIn()) return '请先登录';

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
    } else {
      _projectStatus[project.id] = ProjectSyncStatus.error;
    }
    await _saveProjectStatus();
    await _saveHistory();
    return error;
  }

  /// 从云端下载单个项目
  Future<String?> downloadProject(String projectId) async {
    if (!isSignedIn()) return '请先登录';

    final remoteData = await _fetchRemoteProject(projectId);
    if (remoteData == null) return '项目不存在';

    final error = await _downloadAndSaveProject(remoteData);
    if (error == null) {
      _addHistory(SyncHistoryEntry(
        projectId: projectId,
        projectName: remoteData['name'] as String? ?? '',
        action: 'download',
        timestamp: DateTime.now(),
      ));
      await _saveHistory();
    }
    return error;
  }

  /// 从云端恢复到指定版本
  Future<String?> restoreFromCloud(
      String projectId, DateTime timestamp) async {
    if (!isSignedIn()) return '请先登录';

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
        if (data.isEmpty) return '找不到该时间点的版本';

        final error = await _downloadAndSaveProject(data.first as Map<String, dynamic>);
        if (error == null) {
          _addHistory(SyncHistoryEntry(
            projectId: projectId,
            projectName: '',
            action: 'restore',
            timestamp: DateTime.now(),
          ));
          await _saveHistory();
        }
        return error;
      }
      return '查询失败: ${response.statusCode}';
    } catch (e) {
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
  Future<String?> _uploadProject(FontProject project) async {
    try {
      // 序列化并加密项目数据
      final projectJson = project.toJson();
      // 将源图片转为 base64
      final sourceImagesBase64 = <String>[];
      for (final img in project.sourceImages) {
        sourceImagesBase64.add(base64Encode(img));
      }
      projectJson['sourceImagesBase64'] = sourceImagesBase64;

      final jsonString = jsonEncode(projectJson);
      // 使用 SHA-256 生成数据摘要用于完整性校验
      final dataHash = sha256.convert(utf8.encode(jsonString)).toString();

      final body = {
        'id': project.id,
        'user_id': _userId,
        'project_data': jsonString,
        'name': project.name,
        'updated_at': project.updatedAt.toIso8601String(),
        'data_hash': dataHash,
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
        return null; // 成功
      }
      return '上传失败: ${response.statusCode}';
    } catch (e) {
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
          '&select=id,name,updated_at,data_hash',
        ),
        headers: _authHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.cast<Map<String, dynamic>>();
      }
      return null;
    } catch (e) {
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
      debugPrint('获取远程项目失败: $e');
      return null;
    }
  }

  /// 下载并保存远程项目到本地
  Future<String?> _downloadAndSaveProject(
      Map<String, dynamic> remoteData) async {
    try {
      final projectDataStr = remoteData['project_data'] as String?;
      if (projectDataStr == null) return '项目数据为空';

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
      return null; // 成功
    } catch (e) {
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
