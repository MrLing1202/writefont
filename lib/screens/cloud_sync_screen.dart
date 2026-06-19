import 'dart:async';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/cloud_sync_service.dart';
import '../theme/app_theme.dart';

/// 云同步页面
/// 登录/注册、同步状态、手动同步、自动同步、同步历史
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

  @override
  void initState() {
    super.initState();
    _initScreen();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _initScreen() async {
    await _sync.init();
    await _refreshData();
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
            style: const TextStyle(fontSize: 14, color: WFColors.textSecondary),
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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('保留本地版本',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      Text('上传本地数据覆盖云端',
                          style: TextStyle(fontSize: 12, color: WFColors.textSecondary)),
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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('保留云端版本',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      Text('下载云端数据覆盖本地',
                          style: TextStyle(fontSize: 12, color: WFColors.textSecondary)),
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
              color: WFColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '登录后可将字体项目同步到云端，实现多设备共享',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: WFColors.textSecondary,
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
              color: isActive ? WFColors.primary : WFColors.textSecondary,
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

        // 同步历史
        _buildHistorySectionHeader(),
        _buildHistoryCard(),
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
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: WFColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '数据已加密存储',
                  style: TextStyle(
                    fontSize: 12,
                    color: WFColors.textSecondary,
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
              const Text(
                '同步状态',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textPrimary,
                ),
              ),
              const Spacer(),
              // 最后同步时间
              if (_lastSyncTime != null)
                Text(
                  '上次同步: ${_formatTime(_lastSyncTime!)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: WFColors.textSecondary,
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
                  color: WFColors.textSecondary,
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
                backgroundColor: WFColors.textLight.withValues(alpha: 0.3),
                valueColor: AlwaysStoppedAnimation<Color>(WFColors.primary),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _syncCurrentItem ?? '正在同步...',
              style: TextStyle(
                fontSize: 12,
                color: WFColors.textSecondary,
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
                const Text(
                  '自动同步',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: WFColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '项目修改后自动同步到云端',
                  style: TextStyle(
                    fontSize: 12,
                    color: WFColors.textSecondary,
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
                Icon(Icons.history, size: 36, color: WFColors.textLight),
                const SizedBox(height: 8),
                Text(
                  '暂无同步记录',
                  style: TextStyle(
                    color: WFColors.textSecondary,
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
                  color: WFColors.textLight.withValues(alpha: 0.3),
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
        style: const TextStyle(fontSize: 14, color: WFColors.textPrimary),
      ),
      subtitle: Text(
        _formatTime(entry.timestamp),
        style: TextStyle(fontSize: 12, color: WFColors.textSecondary),
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
}
