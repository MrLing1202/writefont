import 'dart:async';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/cloud_sync_service.dart';
import '../theme/app_theme.dart';

/// 云同步页面
/// 登录/注册、同步状态、手动同步、自动同步、同步历史
/// 协作功能：实时协作、权限管理、协作历史、冲突解决
class CloudSyncScreen extends StatefulWidget {
  const CloudSyncScreen({super.key});

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  final CloudSyncService _sync = CloudSyncService.instance;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = true;
  bool _isAuthenticating = false;
  bool _showPassword = false;
  bool _isLoginMode = true; // true=登录, false=注册
  String? _authError;

  // 同步状态
  Map<String, String> _syncStatusMap = {};
  bool _isSyncing = false;
  String? _syncError;
  List<SyncHistoryEntry> _history = [];

  // 同步进度跟踪
  int _syncTotal = 0;
  int _syncCompleted = 0;
  String? _syncCurrentItem;
  DateTime? _lastSyncTime;

  // ═══════════════════════════════════════════════════════
  // 协作功能状态
  // ═══════════════════════════════════════════════════════

  /// 协作者列表: [{email, role, addedAt, avatarUrl}]
  List<Map<String, dynamic>> _collaborators = [];

  /// 协作权限等级
  static const Map<String, String> _roleLabels = {
    'owner': '所有者',
    'editor': '编辑者',
    'viewer': '查看者',
  };

  /// 协作历史记录
  List<Map<String, dynamic>> _collabHistory = [];

  /// 实时协作者在线状态
  List<Map<String, dynamic>> _onlineCollaborators = [];

  /// 协作邀请邮箱输入
  final TextEditingController _inviteEmailController = TextEditingController();

  // ═══════════════════════════════════════════════════════
  // 社交功能状态
  // ═══════════════════════════════════════════════════════

  /// 好友列表
  List<FriendInfo> _friends = [];

  /// 关注列表
  List<FollowInfo> _following = [];

  /// 粉丝列表
  List<FollowInfo> _followers = [];

  /// 私信列表
  List<DirectMessage> _directMessages = [];

  /// 动态列表
  List<ActivityFeed> _activityFeed = [];

  /// 社交Tab索引
  int _socialTabIndex = 0; // 0=好友, 1=关注, 2=私信, 3=动态

  @override
  void initState() {
    super.initState();
    _initScreen();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _inviteEmailController.dispose();
    super.dispose();
  }

  Future<void> _initScreen() async {
    await _sync.init();
    await _refreshData();
    _loadSocialData();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _refreshData() async {
    final statusMap = await _sync.getSyncStatus();
    final history = await _sync.getSyncHistory();
    if (mounted) {
      setState(() {
        _syncStatusMap = statusMap;
        _history = history;
        // 从历史记录中获取最后同步时间
        if (history.isNotEmpty) {
          _lastSyncTime = history.first.timestamp;
        }
      });
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 认证操作
  // ═══════════════════════════════════════════════════════════

  Future<void> _handleAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _authError = '请输入邮箱和密码');
      return;
    }
    if (password.length < 6) {
      setState(() => _authError = '密码至少 6 位');
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _authError = null;
    });

    final error = _isLoginMode
        ? await _sync.signIn(email, password)
        : await _sync.signUp(email, password);

    if (mounted) {
      setState(() => _isAuthenticating = false);
      if (error == null) {
        WFSnackBar.show(context, _isLoginMode ? '登录成功' : '注册成功');
        _refreshData();
      } else {
        setState(() => _authError = error);
      }
    }
  }

  Future<void> _handleSignOut() async {
    await _sync.signOut();
    if (mounted) {
      setState(() {});
      WFSnackBar.show(context, '已退出登录');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 同步操作
  // ═══════════════════════════════════════════════════════════

  Future<void> _handleSync() async {
    setState(() {
      _isSyncing = true;
      _syncError = null;
      _syncCompleted = 0;
      _syncTotal = _syncStatusMap.length;
      _syncCurrentItem = null;
    });

    final error = await _sync.syncAll();

    if (mounted) {
      setState(() {
        _isSyncing = false;
        _syncCurrentItem = null;
        _lastSyncTime = DateTime.now();
      });
      if (error == null) {
        WFSnackBar.show(context, '同步完成');
      } else {
        setState(() => _syncError = error);
        WFSnackBar.error(context, error);
      }
      _refreshData();
    }
  }

  Future<void> _handleToggleAutoSync(bool value) async {
    await _sync.setAutoSync(value);
    if (mounted) {
      setState(() {});
      WFSnackBar.show(context, value ? '已开启自动同步' : '已关闭自动同步');
    }
  }

  Future<void> _handleRestore(SyncHistoryEntry entry) async {
    final confirmed = await WFDialog.confirm(
      context,
      title: '恢复版本',
      message: '确定要恢复项目"${entry.projectName}"到此版本吗？当前数据将被覆盖。',
      confirmText: '恢复',
      isDestructive: true,
    );

    if (confirmed != true) return;

    setState(() => _isSyncing = true);
    final error = await _sync.restoreFromCloud(entry.projectId, entry.timestamp);
    if (mounted) {
      setState(() => _isSyncing = false);
      if (error == null) {
        WFSnackBar.show(context, '恢复成功');
      } else {
        WFSnackBar.error(context, error);
      }
      _refreshData();
    }
  }

  /// 清除同步历史记录
  Future<void> _clearHistory() async {
    final confirmed = await WFDialog.confirm(
      context,
      title: '清除同步历史',
      message: '确定要清除所有同步历史记录吗？此操作不影响已同步的数据。',
      confirmText: '清除',
      isDestructive: true,
    );

    if (confirmed != true) return;

    setState(() {
      _history.clear();
      _lastSyncTime = null;
    });
    WFSnackBar.show(context, '同步历史已清除');
  }

  // ═══════════════════════════════════════════════════════════
  // 协作功能操作
  // ═══════════════════════════════════════════════════════════

  /// 加载协作者列表
  Future<void> _loadCollaborators() async {
    try {
      final collaborators = await _sync.getCollaborators();
      final online = await _sync.getOnlineCollaborators();
      if (mounted) {
        setState(() {
          _collaborators = collaborators;
          _onlineCollaborators = online;
        });
      }
    } catch (e) {
      debugPrint('加载协作者失败: $e');
    }
  }

  /// 加载协作历史
  Future<void> _loadCollabHistory() async {
    try {
      final history = await _sync.getCollabHistory();
      if (mounted) {
        setState(() => _collabHistory = history);
      }
    } catch (e) {
      debugPrint('加载协作历史失败: $e');
    }
  }

  /// 邀请协作者
  Future<void> _inviteCollaborator(String projectId, String projectName) async {
    _inviteEmailController.clear();
    final result = await WFDialog.show<Map<String, String>>(
      context,
      title: '邀请协作者',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _inviteEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: '协作者邮箱',
              hintText: '输入协作者的邮箱地址',
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '选择权限级别：',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          _buildRoleSelector(),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final email = _inviteEmailController.text.trim();
            if (email.isNotEmpty) {
              Navigator.pop(context, {'email': email, 'role': 'editor'});
            }
          },
          child: const Text('发送邀请'),
        ),
      ],
    );

    if (result == null) return;

    setState(() => _isSyncing = true);
    final error = await _sync.inviteCollaborator(
      projectId: projectId,
      email: result['email']!,
      role: result['role'] ?? 'editor',
    );
    if (mounted) {
      setState(() => _isSyncing = false);
      if (error == null) {
        WFSnackBar.show(context, '已向 ${result["email"]} 发送协作邀请');
        _loadCollaborators();
      } else {
        WFSnackBar.error(context, error);
      }
    }
  }

  /// 移除协作者
  Future<void> _removeCollaborator(String projectId, String email) async {
    final confirmed = await WFDialog.confirm(
      context,
      title: '移除协作者',
      message: '确定要移除 $email 的协作权限吗？',
      confirmText: '移除',
      isDestructive: true,
    );

    if (confirmed != true) return;

    final error = await _sync.removeCollaborator(
      projectId: projectId,
      email: email,
    );
    if (mounted) {
      if (error == null) {
        WFSnackBar.show(context, '已移除 $email');
        _loadCollaborators();
      } else {
        WFSnackBar.error(context, error);
      }
    }
  }

  /// 修改协作者权限
  Future<void> _changeCollaboratorRole(
      String projectId, String email, String newRole) async {
    final error = await _sync.updateCollaboratorRole(
      projectId: projectId,
      email: email,
      role: newRole,
    );
    if (mounted) {
      if (error == null) {
        WFSnackBar.show(context, '已将 $email 的权限更改为${_roleLabels[newRole]}');
        _loadCollaborators();
      } else {
        WFSnackBar.error(context, error);
      }
    }
  }

  /// 构建权限选择器
  Widget _buildRoleSelector() {
    return Column(
      children: _roleLabels.entries
          .where((e) => e.key != 'owner')
          .map((entry) => RadioListTile<String>(
                title: Text(entry.value),
                subtitle: Text(
                  entry.key == 'editor' ? '可以编辑项目' : '仅可查看',
                  style: const TextStyle(fontSize: 12),
                ),
                value: entry.key,
                groupValue: 'editor',
                onChanged: (_) {},
                dense: true,
              ))
          .toList(),
    );
  }

  /// 显示协作冲突解决对话框（增强版）
  Future<void> _showCollabConflictDialog(
      String projectId, String projectName, Map<String, dynamic> conflictInfo) async {
    final choice = await WFDialog.show<String>(
      context,
      title: '协作冲突',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: WFColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: WFColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: WFColors.warning, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '项目"$projectName"被多位协作者同时修改',
                    style: TextStyle(fontSize: 13, color: WFColors.textPrimaryColor(context)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '冲突版本：${conflictInfo['versionCount'] ?? 2} 个',
            style: TextStyle(fontSize: 13, color: WFColors.textSecondaryColor(context)),
          ),
          Text(
            '最后修改者：${conflictInfo['lastEditor'] ?? '未知'}',
            style: TextStyle(fontSize: 13, color: WFColors.textSecondaryColor(context)),
          ),
          Text(
            '修改时间：${conflictInfo['lastEditTime'] ?? '未知'}',
            style: TextStyle(fontSize: 13, color: WFColors.textSecondaryColor(context)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('稍后处理'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'mine'),
          style: TextButton.styleFrom(foregroundColor: WFColors.info),
          child: const Text('使用我的版本'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'theirs'),
          style: TextButton.styleFrom(foregroundColor: WFColors.success),
          child: const Text('使用对方版本'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'merge'),
          style: TextButton.styleFrom(foregroundColor: WFColors.primary),
          child: const Text('合并版本'),
        ),
      ],
    );

    if (choice == null) return;

    setState(() => _isSyncing = true);
    final error = await _sync.resolveCollabConflict(
      projectId: projectId,
      resolution: choice,
    );
    if (mounted) {
      setState(() => _isSyncing = false);
      if (error == null) {
        WFSnackBar.show(context, '冲突已解决');
      } else {
        WFSnackBar.error(context, error);
      }
      _refreshData();
    }
  }

  /// 显示同步冲突解决对话框
  Future<void> _showConflictDialog(String projectId, String projectName) async {
    final choice = await WFDialog.show<String>(
      context,
      title: '同步冲突',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '项目"$projectName"在本地和云端都有修改，请选择保留哪个版本：',
            style: TextStyle(fontSize: 14, color: WFColors.textSecondaryColor(context)),
          ),
          const SizedBox(height: 16),
          // 本地版本选项
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: WFColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: WFColors.info.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.phone_android, color: WFColors.info, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('保留本地版本',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      Text('上传本地数据覆盖云端',
                          style: TextStyle(fontSize: 12, color: WFColors.textSecondaryColor(context))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 云端版本选项
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: WFColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: WFColors.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.cloud_download, color: WFColors.success, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('保留云端版本',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      Text('下载云端数据覆盖本地',
                          style: TextStyle(fontSize: 12, color: WFColors.textSecondaryColor(context))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'local'),
          style: TextButton.styleFrom(foregroundColor: WFColors.info),
          child: const Text('保留本地'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'remote'),
          style: TextButton.styleFrom(foregroundColor: WFColors.success),
          child: const Text('保留云端'),
        ),
      ],
    );

    if (choice == null) return;

    setState(() => _isSyncing = true);
    String? error;

    if (choice == 'local') {
      // 上传本地版本
      final projects = await StorageService.loadProjects();
      final project = projects.where((p) => p.id == projectId).firstOrNull;
      if (project != null) {
        error = await _sync.uploadProject(project);
      }
    } else {
      // 下载云端版本
      error = await _sync.downloadProject(projectId);
    }

    if (mounted) {
      setState(() => _isSyncing = false);
      if (error == null) {
        WFSnackBar.show(context, choice == 'local' ? '已上传本地版本' : '已下载云端版本');
      } else {
        WFSnackBar.error(context, error);
      }
      _refreshData();
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 构建 UI
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const WFAppBar(title: '云同步'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sync.isSignedIn()
              ? _buildSyncView()
              : _buildAuthView(),
    );
  }

  // ── 登录/注册视图 ──

  Widget _buildAuthView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          // 云图标
          Icon(
            Icons.cloud_sync,
            size: 72,
            color: WFColors.primary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 16),
          Text(
            '多设备云同步',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: WFColors.textPrimaryColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '登录后可将字体项目同步到云端，实现多设备共享',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: WFColors.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 32),

          // 切换登录/注册
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTabButton('登录', _isLoginMode),
              const SizedBox(width: 16),
              _buildTabButton('注册', !_isLoginMode),
            ],
          ),
          const SizedBox(height: 24),

          // 邮箱
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: '邮箱',
              hintText: 'your@email.com',
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: WFColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 密码
          TextField(
            controller: _passwordController,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: '密码',
              hintText: '至少 6 位',
              prefixIcon: const Icon(Icons.lock_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _showPassword = !_showPassword),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: WFColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 错误提示
          if (_authError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _authError!,
                style: TextStyle(color: WFColors.error, fontSize: 13),
              ),
            ),

          const SizedBox(height: 16),

          // 提交按钮
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isAuthenticating ? null : _handleAuth,
              style: ElevatedButton.styleFrom(
                backgroundColor: WFColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isAuthenticating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(_isLoginMode ? '登录' : '注册'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, bool isActive) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isLoginMode = label == '登录';
          _authError = null;
        });
      },
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              color: isActive ? WFColors.primary : WFColors.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 2,
            width: 40,
            decoration: BoxDecoration(
              color: isActive ? WFColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }

  // ── 已登录同步视图 ──

  Widget _buildSyncView() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      children: [
        // 用户信息
        _buildUserCard(),
        const SizedBox(height: 16),

        // 同步状态概览
        _buildSyncOverviewCard(),
        const SizedBox(height: 16),

        // 自动同步
        _buildAutoSyncCard(),
        const SizedBox(height: 16),

        // 实时在线协作者
        if (_onlineCollaborators.isNotEmpty) ...[
          _buildOnlineCollaboratorsCard(),
          const SizedBox(height: 16),
        ],

        // 协作管理
        _buildCollaborationSection(),
        const SizedBox(height: 16),

        // 社交互动
        _buildSocialSection(),
        const SizedBox(height: 16),

        // 同步历史
        _buildHistorySectionHeader(),
        _buildHistoryCard(),

        // 协作历史
        if (_collabHistory.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildCollabHistorySection(),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildUserCard() {
    return WFCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: WFColors.primary.withValues(alpha: 0.1),
            child: Icon(Icons.person, color: WFColors.primary, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _sync.userEmail ?? '已登录',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: WFColors.textPrimaryColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '数据已加密存储',
                  style: TextStyle(
                    fontSize: 12,
                    color: WFColors.textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _handleSignOut,
            child: Text('退出', style: TextStyle(color: WFColors.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncOverviewCard() {
    final total = _syncStatusMap.length;
    final synced =
        _syncStatusMap.values.where((s) => s == 'synced').length;
    final pending =
        _syncStatusMap.values.where((s) => s == 'pending').length;
    final errors =
        _syncStatusMap.values.where((s) => s == 'error').length;

    return WFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_done, color: WFColors.success, size: 20),
              const SizedBox(width: 8),
              Text(
                '同步状态',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textPrimaryColor(context),
                ),
              ),
              const Spacer(),
              // 最后同步时间
              if (_lastSyncTime != null)
                Text(
                  '上次同步: ${_formatTime(_lastSyncTime!)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: WFColors.textSecondaryColor(context),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatChip('已同步', synced, WFColors.success),
              const SizedBox(width: 12),
              _buildStatChip('待同步', pending, WFColors.warning),
              const SizedBox(width: 12),
              _buildStatChip('错误', errors, WFColors.error),
              const Spacer(),
              Text(
                '共 $total 个项目',
                style: TextStyle(
                  fontSize: 12,
                  color: WFColors.textSecondaryColor(context),
                ),
              ),
            ],
          ),
          if (_syncError != null) ...[
            const SizedBox(height: 8),
            Text(
              _syncError!,
              style: TextStyle(color: WFColors.error, fontSize: 12),
            ),
          ],
          // 同步进度条
          if (_isSyncing) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 4,
                backgroundColor: WFColors.textLightColor(context).withValues(alpha: 0.3),
                valueColor: AlwaysStoppedAnimation<Color>(WFColors.primary),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _syncCurrentItem ?? '正在同步...',
              style: TextStyle(
                fontSize: 12,
                color: WFColors.textSecondaryColor(context),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              onPressed: _isSyncing ? null : _handleSync,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sync, size: 18),
              label: Text(_isSyncing ? '同步中...' : '立即同步'),
              style: ElevatedButton.styleFrom(
                backgroundColor: WFColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$label $count',
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoSyncCard() {
    return WFCard(
      child: Row(
        children: [
          Icon(Icons.sync, color: WFColors.info, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '自动同步',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: WFColors.textPrimaryColor(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '项目修改后自动同步到云端',
                  style: TextStyle(
                    fontSize: 12,
                    color: WFColors.textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _sync.autoSync,
            onChanged: _handleToggleAutoSync,
            activeColor: WFColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: WFColors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: WFColors.primary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  /// 同步历史区域标题（带清除按钮）
  Widget _buildHistorySectionHeader() {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 8, bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.history, size: 18, color: WFColors.primary),
          const SizedBox(width: 8),
          const Text(
            '同步历史',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: WFColors.primary,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          if (_history.isNotEmpty)
            GestureDetector(
              onTap: _clearHistory,
              child: Text(
                '清除',
                style: TextStyle(
                  fontSize: 12,
                  color: WFColors.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard() {
    if (_history.isEmpty) {
      return WFCard(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(Icons.history, size: 36, color: WFColors.textLightColor(context)),
                const SizedBox(height: 8),
                Text(
                  '暂无同步记录',
                  style: TextStyle(
                    color: WFColors.textSecondaryColor(context),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return WFCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: _history.take(20).toList().asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final isLast = index >= _history.take(20).length - 1;

          return Column(
            children: [
              _buildHistoryItem(item),
              if (!isLast)
                Divider(
                  height: 1,
                  color: WFColors.textLightColor(context).withValues(alpha: 0.3),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHistoryItem(SyncHistoryEntry entry) {
    final actionLabel = {
          'upload': '上传',
          'download': '下载',
          'restore': '恢复',
        }[entry.action] ??
        entry.action;

    final actionIcon = {
          'upload': Icons.cloud_upload,
          'download': Icons.cloud_download,
          'restore': Icons.restore,
        }[entry.action] ??
        Icons.sync;

    final actionColor = entry.success ? WFColors.success : WFColors.error;

    return ListTile(
      leading: Icon(actionIcon, color: actionColor, size: 22),
      title: Text(
        '${entry.projectName} · $actionLabel',
        style: TextStyle(fontSize: 14, color: WFColors.textPrimaryColor(context)),
      ),
      subtitle: Text(
        _formatTime(entry.timestamp),
        style: TextStyle(fontSize: 12, color: WFColors.textSecondaryColor(context)),
      ),
      trailing: entry.action != 'restore'
          ? IconButton(
              icon: Icon(Icons.restore, size: 20, color: WFColors.info),
              tooltip: '恢复到此版本',
              onPressed: () => _handleRestore(entry),
            )
          : null,
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${time.month}/${time.day} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }

  // ═══════════════════════════════════════════════════════════
  // 协作 UI 组件
  // ═══════════════════════════════════════════════════════════

  /// 实时在线协作者卡片
  Widget _buildOnlineCollaboratorsCard() {
    return WFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people, color: WFColors.success, size: 20),
              const SizedBox(width: 8),
              Text(
                '在线协作者',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textPrimaryColor(context),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: WFColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_onlineCollaborators.length} 人在线',
                  style: TextStyle(fontSize: 11, color: WFColors.success),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _onlineCollaborators.map((collab) {
              return Chip(
                avatar: CircleAvatar(
                  backgroundColor: WFColors.success.withValues(alpha: 0.2),
                  child: Text(
                    (collab['email'] as String? ?? '?')[0].toUpperCase(),
                    style: TextStyle(fontSize: 12, color: WFColors.success),
                  ),
                ),
                label: Text(
                  collab['email'] as String? ?? '未知',
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: WFColors.success.withValues(alpha: 0.05),
                side: BorderSide(color: WFColors.success.withValues(alpha: 0.2)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// 协作管理区域
  Widget _buildCollaborationSection() {
    return WFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.group_add, color: WFColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                '协作管理',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textPrimaryColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 邀请按钮
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              onPressed: () => _showInviteCollaboratorSheet(),
              icon: const Icon(Icons.person_add, size: 18),
              label: const Text('邀请协作者'),
              style: OutlinedButton.styleFrom(
                foregroundColor: WFColors.primary,
                side: BorderSide(color: WFColors.primary.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          // 协作者列表
          if (_collaborators.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ..._collaborators.map((collab) => _buildCollaboratorItem(collab)),
          ],
        ],
      ),
    );
  }

  /// 构建协作者列表项
  Widget _buildCollaboratorItem(Map<String, dynamic> collab) {
    final email = collab['email'] as String? ?? '';
    final role = collab['role'] as String? ?? 'viewer';
    final isOnline = _onlineCollaborators.any((o) => o['email'] == email);

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: WFColors.primary.withValues(alpha: 0.1),
            child: Text(
              email.isNotEmpty ? email[0].toUpperCase() : '?',
              style: TextStyle(fontSize: 14, color: WFColors.primary),
            ),
          ),
          if (isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: WFColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
      title: Text(email, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        _roleLabels[role] ?? role,
        style: TextStyle(fontSize: 12, color: WFColors.textSecondaryColor(context)),
      ),
      trailing: role != 'owner'
          ? PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 18, color: WFColors.textSecondaryColor(context)),
              onSelected: (value) {
                if (value == 'remove') {
                  _removeCollaborator('', email);
                } else if (value == 'editor' || value == 'viewer') {
                  _changeCollaboratorRole('', email, value);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'editor', child: Text('设为编辑者')),
                const PopupMenuItem(value: 'viewer', child: Text('设为查看者')),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'remove',
                  child: Text('移除', style: TextStyle(color: WFColors.error)),
                ),
              ],
            )
          : null,
    );
  }

  /// 显示邀请协作者底部面板
  void _showInviteCollaboratorSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '邀请协作者',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '邀请他人一起编辑字体项目，支持实时协作',
              style: TextStyle(fontSize: 13, color: WFColors.textSecondaryColor(context)),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _inviteEmailController,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '邮箱地址',
                hintText: 'collaborator@email.com',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('权限级别', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _buildRoleSelector(),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  final email = _inviteEmailController.text.trim();
                  if (email.isNotEmpty) {
                    Navigator.pop(ctx);
                    _inviteCollaborator('', email);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: WFColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('发送邀请'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 协作历史区域
  Widget _buildCollabHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('协作历史', Icons.history_edu),
        WFCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: _collabHistory.take(10).toList().asMap().entries.map((entry) {
              final item = entry.value;
              final isLast = entry.key >= _collabHistory.take(10).length - 1;

              return Column(
                children: [
                  ListTile(
                    dense: true,
                    leading: Icon(
                      _getCollabActionIcon(item['action'] as String? ?? ''),
                      size: 20,
                      color: WFColors.info,
                    ),
                    title: Text(
                      '${item['user'] ?? '未知'} ${_getCollabActionLabel(item['action'] as String? ?? '')}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      _formatTime(DateTime.tryParse(item['timestamp'] as String? ?? '') ?? DateTime.now()),
                      style: TextStyle(fontSize: 11, color: WFColors.textSecondaryColor(context)),
                    ),
                  ),
                  if (!isLast)
                    Divider(height: 1, color: WFColors.textLightColor(context).withValues(alpha: 0.3)),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 社交功能操作
  // ═══════════════════════════════════════════════════════════

  /// 加载社交数据
  Future<void> _loadSocialData() async {
    try {
      if (mounted) {
        setState(() {
          _friends = _sync.friends;
          _following = _sync.following;
          _followers = _sync.followers;
          _directMessages = _sync.getConversation('');
          _activityFeed = _sync.activityFeed;
        });
      }
    } catch (e) {
      debugPrint('加载社交数据失败: $e');
    }
  }

  /// 发送好友请求
  Future<void> _sendFriendRequest(String friendId, String friendName) async {
    setState(() => _isSyncing = true);
    final error = await _sync.addFriend(friendId, friendName);
    if (mounted) {
      setState(() => _isSyncing = false);
      if (error == null) {
        WFSnackBar.show(context, '好友请求已发送');
        _loadSocialData();
      } else {
        WFSnackBar.error(context, error);
      }
    }
  }

  /// 关注用户
  Future<void> _followUser(String userId, String userName) async {
    setState(() => _isSyncing = true);
    final error = await _sync.followUser(userId, userName);
    if (mounted) {
      setState(() => _isSyncing = false);
      if (error == null) {
        WFSnackBar.show(context, '已关注 $userName');
        _loadSocialData();
      } else {
        WFSnackBar.error(context, error);
      }
    }
  }

  /// 发送私信
  Future<void> _sendDirectMessage(String receiverId, String content) async {
    final error = await _sync.sendDirectMessage(
      receiverId: receiverId,
      content: content,
    );
    if (mounted) {
      if (error == null) {
        WFSnackBar.show(context, '私信已发送');
        _loadSocialData();
      } else {
        WFSnackBar.error(context, error);
      }
    }
  }

  /// 构建社交功能区域
  Widget _buildSocialSection() {
    return WFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people_alt, color: WFColors.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                '社交互动',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WFColors.textPrimaryColor(context)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSocialTab('好友', 0, Icons.person),
              const SizedBox(width: 8),
              _buildSocialTab('关注', 1, Icons.person_add),
              const SizedBox(width: 8),
              _buildSocialTab('私信', 2, Icons.message),
              const SizedBox(width: 8),
              _buildSocialTab('动态', 3, Icons.dynamic_feed),
            ],
          ),
          const SizedBox(height: 12),
          _buildSocialContent(),
        ],
      ),
    );
  }

  /// 构建社交Tab按钮
  Widget _buildSocialTab(String label, int index, IconData icon) {
    final isActive = _socialTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _socialTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? WFColors.primary.withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isActive ? WFColors.primary : WFColors.textLightColor(context).withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: isActive ? WFColors.primary : WFColors.textSecondaryColor(context)),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 11, color: isActive ? WFColors.primary : WFColors.textSecondaryColor(context), fontWeight: isActive ? FontWeight.w600 : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建社交内容区域
  Widget _buildSocialContent() {
    switch (_socialTabIndex) {
      case 0: return _buildFriendsList();
      case 1: return _buildFollowingList();
      case 2: return _buildDirectMessagesList();
      case 3: return _buildActivityFeedList();
      default: return _buildFriendsList();
    }
  }

  /// 构建好友列表
  Widget _buildFriendsList() {
    if (_friends.isEmpty) return _buildEmptySocialState('暂无好友', '点击下方按钮添加好友');
    return Column(
      children: _friends.take(5).map((friend) => ListTile(
        dense: true, contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(radius: 16, backgroundColor: WFColors.accent.withValues(alpha: 0.1), child: Text(friend.friendName.isNotEmpty ? friend.friendName[0].toUpperCase() : '?', style: TextStyle(fontSize: 14, color: WFColors.accent))),
        title: Text(friend.friendName, style: const TextStyle(fontSize: 14)),
        subtitle: Text(friend.status == 'accepted' ? '已添加' : '待接受', style: TextStyle(fontSize: 12, color: WFColors.textSecondaryColor(context))),
        trailing: friend.status == 'pending' ? TextButton(onPressed: () { _sync.acceptFriendRequest(friend.friendId).then((_) => _loadSocialData()); }, child: const Text('接受', style: TextStyle(fontSize: 12))) : null,
      )).toList(),
    );
  }

  /// 构建关注列表
  Widget _buildFollowingList() {
    if (_following.isEmpty) return _buildEmptySocialState('暂无关注', '关注感兴趣的用户');
    return Column(
      children: _following.take(5).map((follow) => ListTile(
        dense: true, contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(radius: 16, backgroundColor: WFColors.info.withValues(alpha: 0.1), child: Text(follow.targetName.isNotEmpty ? follow.targetName[0].toUpperCase() : '?', style: TextStyle(fontSize: 14, color: WFColors.info))),
        title: Text(follow.targetName, style: const TextStyle(fontSize: 14)),
        trailing: IconButton(icon: Icon(Icons.person_remove, size: 18, color: WFColors.textSecondaryColor(context)), onPressed: () async { await _sync.unfollowUser(follow.targetId); _loadSocialData(); }),
      )).toList(),
    );
  }

  /// 构建私信列表
  Widget _buildDirectMessagesList() {
    if (_directMessages.isEmpty) return _buildEmptySocialState('暂无私信', '与好友分享您的创作');
    return Column(
      children: _directMessages.take(5).map((msg) => ListTile(
        dense: true, contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(radius: 16, backgroundColor: WFColors.success.withValues(alpha: 0.1), child: Text(msg.senderName.isNotEmpty ? msg.senderName[0].toUpperCase() : '?', style: TextStyle(fontSize: 14, color: WFColors.success))),
        title: Text(msg.content, style: const TextStyle(fontSize: 13)),
        subtitle: Text(_formatTime(msg.timestamp), style: TextStyle(fontSize: 11, color: WFColors.textSecondaryColor(context))),
      )).toList(),
    );
  }

  /// 构建动态列表
  Widget _buildActivityFeedList() {
    if (_activityFeed.isEmpty) return _buildEmptySocialState('暂无动态', '分享您的创作动态');
    return Column(
      children: _activityFeed.take(5).map((activity) {
        final icon = activity.type == 'friend_request' ? Icons.person_add : activity.type == 'follow' ? Icons.favorite : activity.type == 'share' ? Icons.share : Icons.notifications;
        final color = activity.type == 'friend_request' ? WFColors.accent : activity.type == 'follow' ? WFColors.error : activity.type == 'share' ? WFColors.info : WFColors.primary;
        return ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(icon, size: 20, color: color), title: Text(activity.content, style: TextStyle(fontSize: 13)), subtitle: Text(_formatTime(activity.timestamp), style: TextStyle(fontSize: 11, color: WFColors.textSecondaryColor(context))));
      }).toList(),
    );
  }

  /// 构建空社交状态
  Widget _buildEmptySocialState(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Column(children: [
          Icon(Icons.people_outline, size: 36, color: WFColors.textLightColor(context)),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(color: WFColors.textSecondaryColor(context), fontSize: 14)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: WFColors.textLightColor(context), fontSize: 12)),
        ]),
      ),
    );
  }

  /// 获取协作操作图标
  IconData _getCollabActionIcon(String action) {
    switch (action) {
      case 'join':
        return Icons.person_add;
      case 'leave':
        return Icons.person_remove;
      case 'edit':
        return Icons.edit;
      case 'invite':
        return Icons.mail;
      case 'role_change':
        return Icons.admin_panel_settings;
      default:
        return Icons.circle;
    }
  }

  /// 获取协作操作标签
  String _getCollabActionLabel(String action) {
    switch (action) {
      case 'join':
        return '加入了协作';
      case 'leave':
        return '离开了协作';
      case 'edit':
        return '编辑了项目';
      case 'invite':
        return '被邀请加入';
      case 'role_change':
        return '权限已变更';
      default:
        return action;
    }
  }
}
