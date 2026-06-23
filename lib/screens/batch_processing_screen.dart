import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/batch_processor.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// 批量处理页面
///
/// 支持批量导出 TTF、批量导出备份、批量删除。
/// 提供多选模式、实时进度显示和取消功能。
class BatchProcessingScreen extends StatefulWidget {
  /// 可选：外部传入预选中的项目 ID 列表
  final List<String>? preSelectedIds;

  const BatchProcessingScreen({super.key, this.preSelectedIds});

  @override
  State<BatchProcessingScreen> createState() => _BatchProcessingScreenState();
}

class _BatchProcessingScreenState extends State<BatchProcessingScreen> {
  List<FontProject> _projects = [];
  final Set<String> _selectedIds = {};
  bool _isLoading = true;

  // 批量处理状态
  final BatchProcessor _processor = BatchProcessor();
  bool _isProcessing = false;
  BatchProgress? _progress;
  List<BatchTaskResult>? _results;

  // 计时器：记录批量处理开始时间和已用时间
  DateTime? _processStartTime;
  String _elapsedTime = '';

  /// 取消当前任务
  void _cancelProcessing() {
    _processor.cancel();
    WFSnackBar.show(context, '正在取消...');
  }

  /// 更新已用时间显示
  void _updateElapsedTime() {
    if (_processStartTime == null) return;
    final elapsed = DateTime.now().difference(_processStartTime!);
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;
    if (mounted) {
      setState(() {
        _elapsedTime = minutes > 0
            ? '$minutes 分 $seconds 秒'
            : '$seconds 秒';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() => _isLoading = true);
    try {
      final projects = await StorageService.loadProjects();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _isLoading = false;
        // 应用预选中
        if (widget.preSelectedIds != null) {
          _selectedIds.addAll(widget.preSelectedIds!);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      WFSnackBar.error(context, '加载项目失败: $e');
    }
  }

  /// 全选/取消全选
  void _toggleSelectAll() {
    setState(() {
      if (_selectedIds.length == _projects.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.clear();
        _selectedIds.addAll(_projects.map((p) => p.id));
      }
    });
  }

  /// 切换单个项目的选中状态
  void _toggleSelection(String projectId) {
    setState(() {
      if (_selectedIds.contains(projectId)) {
        _selectedIds.remove(projectId);
      } else {
        _selectedIds.add(projectId);
      }
    });
  }

  /// 获取选中的项目列表
  List<FontProject> get _selectedProjects =>
      _projects.where((p) => _selectedIds.contains(p.id)).toList();

  // ── 批量操作 ──

  /// 批量导出 TTF
  Future<void> _batchExportTtf() async {
    final projects = _selectedProjects;
    if (projects.isEmpty) {
      WFSnackBar.show(context, '请先选择要导出的项目');
      return;
    }

    final confirmed = await WFDialog.confirm(
      context,
      title: '批量导出 TTF',
      message: '将为选中的 ${projects.length} 个项目生成 TTF 字体文件，是否继续？',
      confirmText: '开始导出',
      icon: Icons.font_download,
      iconColor: WFColors.info,
    );

    if (confirmed != true) return;

    setState(() {
      _processStartTime = DateTime.now();
      _isProcessing = true;
      _progress = null;
      _results = null;
    });

    try {
      final results = await _processor.batchExportTtf(
        projects,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _progress = progress);
            _updateElapsedTime();
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _results = results;
      });

      _showResults('批量导出 TTF', results, canRetry: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      WFSnackBar.error(context, '批量导出失败: $e');
    }
  }

  /// 批量导出备份
  Future<void> _batchExportBackup() async {
    final projects = _selectedProjects;
    if (projects.isEmpty) {
      WFSnackBar.show(context, '请先选择要备份的项目');
      return;
    }

    final confirmed = await WFDialog.confirm(
      context,
      title: '批量导出备份',
      message: '将为选中的 ${projects.length} 个项目生成 JSON 备份文件，是否继续？',
      confirmText: '开始备份',
      icon: Icons.backup,
      iconColor: WFColors.info,
    );

    if (confirmed != true) return;

    setState(() {
      _processStartTime = DateTime.now();
      _isProcessing = true;
      _progress = null;
      _results = null;
    });

    try {
      final results = await _processor.batchExportBackup(
        projects,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _progress = progress);
            _updateElapsedTime();
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _results = results;
      });

      _showResults('批量导出备份', results, canRetry: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      WFSnackBar.error(context, '批量备份失败: $e');
    }
  }

  /// 批量删除
  Future<void> _batchDelete() async {
    final projects = _selectedProjects;
    if (projects.isEmpty) {
      WFSnackBar.show(context, '请先选择要删除的项目');
      return;
    }

    final confirmed = await WFDialog.confirm(
      context,
      title: '批量删除',
      message: '确定要删除选中的 ${projects.length} 个项目吗？\n该操作不可撤销。',
      confirmText: '删除',
      isDestructive: true,
      icon: Icons.delete_forever,
      iconColor: WFColors.error,
    );

    if (confirmed != true) return;

    setState(() {
      _processStartTime = DateTime.now();
      _isProcessing = true;
      _progress = null;
      _results = null;
    });

    try {
      final results = await _processor.batchDelete(
        projects,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _progress = progress);
            _updateElapsedTime();
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _results = results;
        // 删除成功的项目从选中列表中移除
        for (final r in results) {
          if (r.success) _selectedIds.remove(r.projectId);
        }
      });

      // 重新加载项目列表
      await _loadProjects();

      _showResults('批量删除', results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      WFSnackBar.error(context, '批量删除失败: $e');
    }
  }

  /// 取消当前任务
  /// 显示结果摘要（含用时统计和重试功能）
  void _showResults(String title, List<BatchTaskResult> results, {bool canRetry = false}) {
    final successCount = results.where((r) => r.success).length;
    final failureCount = results.where((r) => !r.success).length;
    final elapsed = _processStartTime != null
        ? DateTime.now().difference(_processStartTime!)
        : null;

    showDialog(
      context: context,
      builder: (_) => _ResultsDialog(
        title: title,
        results: results,
        successCount: successCount,
        failureCount: failureCount,
        elapsed: elapsed,
        canRetry: canRetry,
        onRetryFailed: canRetry ? () => _retryFailedItems(results) : null,
      ),
    );
  }

  /// 重试失败的项目
  Future<void> _retryFailedItems(List<BatchTaskResult> results) async {
    final failedIds = results
        .where((r) => !r.success && r.errorMessage != '已取消')
        .map((r) => r.projectId)
        .toList();

    if (failedIds.isEmpty) {
      WFSnackBar.show(context, '没有需要重试的项目');
      return;
    }

    // 关闭结果对话框
    Navigator.pop(context);

    // 重新选中失败的项目
    setState(() {
      _selectedIds.clear();
      _selectedIds.addAll(failedIds);
    });

    WFSnackBar.show(context, '已选中 ${failedIds.length} 个失败项目，请重新执行操作');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: WFAppBar(
        title: '批量处理',
        actions: [
          if (!_isProcessing) ...[
            IconButton(
              onPressed: _toggleSelectAll,
              icon: Icon(
                _selectedIds.length == _projects.length && _projects.isNotEmpty
                    ? Icons.deselect
                    : Icons.select_all,
              ),
              tooltip: _selectedIds.length == _projects.length && _projects.isNotEmpty
                  ? '取消全选'
                  : '全选',
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _projects.isEmpty
              ? _buildEmptyState(colorScheme)
              : _isProcessing
                  ? _buildProcessingView(colorScheme)
                  : _buildProjectList(colorScheme),
      // 底部操作栏
      bottomNavigationBar:
          _isProcessing ? null : _buildBottomBar(colorScheme),
    );
  }

  /// 空状态
  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            '还没有项目',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '先创建一些字体项目再来批量处理',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  /// 项目列表（多选模式）
  Widget _buildProjectList(ColorScheme colorScheme) {
    return Column(
      children: [
        // 选中数量提示
        if (_selectedIds.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Row(
              children: [
                Icon(Icons.check_circle,
                    size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '已选择 ${_selectedIds.length} / ${_projects.length} 个项目',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        // 项目列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _projects.length,
            itemBuilder: (ctx, index) {
              final project = _projects[index];
              final isSelected = _selectedIds.contains(project.id);
              return _buildSelectableCard(
                project: project,
                colorScheme: colorScheme,
                isSelected: isSelected,
                onToggle: () => _toggleSelection(project.id),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 可选项目卡片
  Widget _buildSelectableCard({
    required FontProject project,
    required ColorScheme colorScheme,
    required bool isSelected,
    required VoidCallback onToggle,
  }) {
    final totalChars = project.glyphs.length;
    final editedChars =
        project.glyphs.values.where((g) => g.contours.isNotEmpty).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isSelected
          ? colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 选中状态
              Icon(
                isSelected
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                size: 28,
              ),
              const SizedBox(width: 12),
              // 项目图标
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    project.glyphs.isNotEmpty
                        ? project.glyphs.keys.first
                        : '字',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 项目信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$totalChars 个字符 · 已编辑 $editedChars',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 处理中视图
  Widget _buildProcessingView(ColorScheme colorScheme) {
    final progress = _progress;
    final progressValue = progress?.progress ?? 0.0;
    final completed = progress?.completed ?? 0;
    final total = progress?.total ?? 0;
    final successCount = progress?.successCount ?? 0;
    final failureCount = progress?.failureCount ?? 0;
    final currentName = progress?.currentProjectName;
    final isCancelled = progress?.isCancelled ?? false;

    // v4.6.0: 改进 ETA 计算 — 基于已完成数量和已用时间
    String? estimatedRemaining;
    double? speed; // 每秒处理项目数
    if (_processStartTime != null && completed > 0 && completed < total) {
      final elapsed = DateTime.now().difference(_processStartTime!);
      final elapsedSec = elapsed.inMilliseconds / 1000.0;
      if (elapsedSec > 0) {
        speed = completed / elapsedSec;
        final remainingItems = total - completed;
        final remainingSec = speed > 0 ? remainingItems / speed : 0;
        if (remainingSec > 0) {
          final remMinutes = (remainingSec / 60).floor();
          final remSeconds = (remainingSec % 60).round();
          estimatedRemaining = remMinutes > 0
              ? '预计剩余 $remMinutes 分 $remSeconds 秒'
              : '预计剩余 $remSeconds 秒';
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 动画图标
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progressValue),
            duration: const Duration(milliseconds: 300),
            builder: (context, value, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      value: value,
                      strokeWidth: 8,
                      backgroundColor:
                          colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isCancelled ? WFColors.warning : colorScheme.primary,
                      ),
                    ),
                  ),
                  Text(
                    '${(value * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),

          // 进度文字
          Text(
            isCancelled ? '正在取消...' : '正在处理...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          // v4.6.0: 进度百分比 + 已完成/总数
          Text(
            '${(progressValue * 100).toStringAsFixed(1)}%  ·  $completed / $total',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          // v4.6.0: 时间信息行（已用时间 + 预估剩余 + 速度）
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              // 已用时间
              if (_elapsedTime.isNotEmpty)
                _buildProgressInfoChip(
                  icon: Icons.timer_outlined,
                  label: '已用 $_elapsedTime',
                  colorScheme: colorScheme,
                ),
              // 预估剩余
              if (estimatedRemaining != null)
                _buildProgressInfoChip(
                  icon: Icons.schedule,
                  label: estimatedRemaining!.replaceAll('预计剩余 ', ''),
                  colorScheme: colorScheme,
                ),
              // 处理速度
              if (speed != null && speed > 0)
                _buildProgressInfoChip(
                  icon: Icons.speed,
                  label: '${speed.toStringAsFixed(1)} 项/秒',
                  colorScheme: colorScheme,
                ),
            ],
          ),
          if (currentName != null) ...[
            const SizedBox(height: 8),
            Text(
              '当前: $currentName',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: 24),

          // 统计信息
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStatChip(
                icon: Icons.check_circle,
                label: '成功 $successCount',
                color: WFColors.success,
                colorScheme: colorScheme,
              ),
              const SizedBox(width: 16),
              _buildStatChip(
                icon: Icons.error,
                label: '失败 $failureCount',
                color: failureCount > 0 ? WFColors.error : colorScheme.onSurfaceVariant,
                colorScheme: colorScheme,
              ),
            ],
          ),

          const SizedBox(height: 32),

          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progressValue,
              minHeight: 8,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                isCancelled ? WFColors.warning : colorScheme.primary,
              ),
            ),
          ),

          const SizedBox(height: 32),

          // 取消按钮
          if (!isCancelled)
            OutlinedButton.icon(
              onPressed: _cancelProcessing,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('取消'),
              style: OutlinedButton.styleFrom(
                foregroundColor: WFColors.error,
                side: const BorderSide(color: WFColors.error),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
        ],
      ),
    );
  }

  /// 统计小标签
  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// v4.6.0: 进度信息小标签（用于 ETA、速度等显示）
  Widget _buildProgressInfoChip({
    required IconData icon,
    required String label,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  /// 底部操作栏
  Widget _buildBottomBar(ColorScheme colorScheme) {
    final hasSelection = _selectedIds.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 批量操作按钮
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.font_download,
                    label: '导出 TTF',
                    color: WFColors.info,
                    enabled: hasSelection,
                    onPressed: _batchExportTtf,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.backup,
                    label: '导出备份',
                    color: WFColors.success,
                    enabled: hasSelection,
                    onPressed: _batchExportBackup,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.delete_forever,
                    label: '批量删除',
                    color: WFColors.error,
                    enabled: hasSelection,
                    onPressed: _batchDelete,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 操作按钮
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return FilledButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: color.withValues(alpha: 0.3),
        disabledForegroundColor: color.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

/// 结果统计对话框
class _ResultsDialog extends StatelessWidget {
  final String title;
  final List<BatchTaskResult> results;
  final int successCount;
  final int failureCount;
  final Duration? elapsed;
  final bool canRetry;
  final VoidCallback? onRetryFailed;

  const _ResultsDialog({
    required this.title,
    required this.results,
    required this.successCount,
    required this.failureCount,
    this.elapsed,
    this.canRetry = false,
    this.onRetryFailed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return WFDialog(
      title: '$title 完成',
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 统计摘要
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildResultStat(
                      icon: Icons.check_circle,
                      label: '成功',
                      count: successCount,
                      color: WFColors.success,
                    ),
                    Container(
                      width: 1,
                      height: 32,
                      color: colorScheme.outlineVariant,
                    ),
                    _buildResultStat(
                      icon: Icons.error,
                      label: '失败',
                      count: failureCount,
                      color: failureCount > 0
                          ? WFColors.error
                          : colorScheme.onSurfaceVariant,
                    ),
                    if (elapsed != null) ...[
                      Container(
                        width: 1,
                        height: 32,
                        color: colorScheme.outlineVariant,
                      ),
                      _buildResultStat(
                        icon: Icons.timer,
                        label: '用时',
                        count: elapsed!.inSeconds,
                        color: WFColors.info,
                        suffix: '秒',
                      ),
                    ],
                  ],
                ),
                ),
              const SizedBox(height: 16),

              // 详细结果列表
              ...results.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          r.success
                              ? Icons.check_circle_outline
                              : Icons.highlight_off,
                          size: 18,
                          color: r.success ? WFColors.success : WFColors.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.projectName,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (!r.success && r.errorMessage != null)
                                Text(
                                  r.errorMessage!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: WFColors.error,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (r.success && r.outputPath != null)
                                Text(
                                  r.outputPath!.split('/').last,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ),
      actions: [
        if (canRetry && failureCount > 0)
          OutlinedButton.icon(
            onPressed: onRetryFailed,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text('重试失败项 ($failureCount)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: WFColors.warning,
              side: const BorderSide(color: WFColors.warning),
            ),
          ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    );
  }

  Widget _buildResultStat({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    String suffix = '',
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          suffix.isNotEmpty ? '$count$suffix' : '$count',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
