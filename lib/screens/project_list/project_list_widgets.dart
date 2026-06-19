import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../data/standard_charset.dart';
import '../../theme/app_theme.dart';
import '../character_grid_screen.dart';
import 'sort_mode.dart';

/// ProjectListScreen 的 Widget 构建方法集合
mixin ProjectListWidgets {
  /// 搜索框
  Widget buildSearchBar({
    required ColorScheme colorScheme,
    required TextEditingController searchController,
    required String searchQuery,
    required ValueChanged<String> onChanged,
    required VoidCallback onClear,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: searchController,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: '搜索项目名称...',
          hintStyle: TextStyle(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          prefixIcon: Icon(Icons.search, color: colorScheme.onSurfaceVariant),
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: onClear,
                )
              : null,
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
        ),
      ),
    );
  }

  /// 搜索无结果提示
  Widget buildSearchEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 56,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              '没有找到匹配的项目',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '试试其他关键词',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 空状态提示（无项目时）
  Widget buildEmptyState({
    required ColorScheme colorScheme,
    required VoidCallback onCreateProject,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.font_download_outlined,
                size: 60,
                color: colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '还没有手迹字体项目',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '点击下方按钮开始创建你的第一款手写字体',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onCreateProject,
              icon: const Icon(Icons.add),
              label: const Text('新建项目'),
            ),
          ],
        ),
      ),
    );
  }

  /// 项目列表（支持滑动删除）
  Widget buildProjectList({
    required ColorScheme colorScheme,
    required List<FontProject> projects,
    required Future<void> Function() onRefresh,
    required Future<void> Function(FontProject) onDelete,
    required Future<void> Function(FontProject) onRename,
    required Future<void> Function(FontProject) onDuplicate,
    required Future<void> Function(FontProject) onExport,
    required Future<void> Function(FontProject) onExportBackup,
    required void Function(FontProject) onOpen,
    required void Function(FontProject) onShowActions,
    required Future<void> Function() onLoadProjects,
    required Future<void> Function(FontProject) onDirectDelete,
    required String searchQuery,
    required BuildContext context,
    bool isMultiSelectMode = false,
    Set<String>? selectedProjectIds,
    void Function(String)? onToggleSelection,
  }) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: projects.length,
        itemBuilder: (ctx, index) {
          final project = projects[index];
          // 多选模式下显示选中卡片
          if (isMultiSelectMode) {
            final isSelected = selectedProjectIds?.contains(project.id) ?? false;
            return _buildSelectableCard(
              project: project,
              colorScheme: colorScheme,
              isSelected: isSelected,
              onToggle: () => onToggleSelection?.call(project.id),
              onOpen: onOpen,
              context: context,
            );
          }
          return buildDismissibleCard(
            project: project,
            colorScheme: colorScheme,
            onDelete: onDelete,
            onRename: onRename,
            onDuplicate: onDuplicate,
            onExport: onExport,
            onExportBackup: onExportBackup,
            onOpen: onOpen,
            onShowActions: onShowActions,
            onLoadProjects: onLoadProjects,
            onDirectDelete: onDirectDelete,
            searchQuery: searchQuery,
            context: context,
          );
        },
      ),
    );
  }

  /// 可滑动删除的项目卡片
  Widget buildDismissibleCard({
    required FontProject project,
    required ColorScheme colorScheme,
    required Future<void> Function(FontProject) onDelete,
    required Future<void> Function(FontProject) onRename,
    required Future<void> Function(FontProject) onDuplicate,
    required Future<void> Function(FontProject) onExport,
    required Future<void> Function(FontProject) onExportBackup,
    required void Function(FontProject) onOpen,
    required void Function(FontProject) onShowActions,
    required Future<void> Function() onLoadProjects,
    required Future<void> Function(FontProject) onDirectDelete,
    required String searchQuery,
    required BuildContext context,
  }) {
    return Dismissible(
      key: Key(project.id),
      direction: DismissDirection.endToStart,
      // 红色删除背景
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: colorScheme.error,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.delete,
              color: colorScheme.onError,
              size: 32,
            ),
            const SizedBox(height: 4),
            Text(
              '删除',
              style: TextStyle(
                color: colorScheme.onError,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        // 二次确认
        return await WFDialog.show<bool>(
          context,
          title: '确认删除',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('确定要删除「${project.name}」吗？'),
              const SizedBox(height: 8),
              // 项目信息预览
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${project.glyphs.length} 个字符 · 创建于 ${formatDate(project.createdAt)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '该操作不可撤销',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: WFColors.error,
              ),
              child: const Text('删除'),
            ),
          ],
        );
      },
      onDismissed: (direction) async {
        try {
          await onDirectDelete(project);
          if (context.mounted) {
            WFSnackBar.show(
              context,
              '「${project.name}」已删除',
              action: SnackBarAction(label: '知道了', onPressed: () {}),
            );
          }
        } catch (e) {
          if (context.mounted) {
            WFSnackBar.error(context, '删除失败: $e');
          }
          // 删除失败时重新加载
          await onLoadProjects();
        }
      },
      child: buildProjectCard(
        project: project,
        colorScheme: colorScheme,
        onOpen: onOpen,
        onShowActions: onShowActions,
        onRename: onRename,
        onDuplicate: onDuplicate,
        onExport: onExport,
        onExportBackup: onExportBackup,
        onDelete: onDelete,
        onLoadProjects: onLoadProjects,
        searchQuery: searchQuery,
        context: context,
      ),
    );
  }

  /// 单个项目卡片（带统计信息和长按菜单）
  Widget buildProjectCard({
    required FontProject project,
    required ColorScheme colorScheme,
    required void Function(FontProject) onOpen,
    required void Function(FontProject) onShowActions,
    required Future<void> Function(FontProject) onRename,
    required Future<void> Function(FontProject) onDuplicate,
    required Future<void> Function(FontProject) onExport,
    required Future<void> Function(FontProject) onExportBackup,
    required Future<void> Function(FontProject) onDelete,
    required Future<void> Function() onLoadProjects,
    required String searchQuery,
    required BuildContext context,
  }) {
    final stats = getProjectStats(project);
    final totalChars = stats.$1;
    final editedChars = stats.$2;
    final standardTotal = stats.$3;
    final standardEdited = stats.$4;
    final progress = stats.$5;
    final createdStr = formatDate(project.createdAt);
    final updatedStr = formatDate(project.updatedAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => onOpen(project),
        onLongPress: () => onShowActions(project),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  // 项目图标
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        project.glyphs.isNotEmpty
                            ? project.glyphs.keys.first
                            : '字',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // 项目信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        buildHighlightedName(project.name, colorScheme, searchQuery),
                        const SizedBox(height: 4),
                        // 统计信息
                        Row(
                          children: [
                            Icon(
                              Icons.text_fields,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$totalChars 个字符',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.edit_note,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '已编辑 $editedChars',
                              style: TextStyle(
                                fontSize: 13,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 12,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '创建于 $createdStr',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.access_time,
                              size: 12,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              updatedStr,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 操作按钮
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'rename':
                          onRename(project);
                          break;
                        case 'duplicate':
                          onDuplicate(project);
                          break;
                        case 'export':
                          onExport(project);
                          break;
                        case 'exportBackup':
                          onExportBackup(project);
                          break;
                        case 'grid':
                          Navigator.push(
                            context,
                            WFAnimations.slideRoute(CharacterGridScreen(project: project)),
                          ).then((_) => onLoadProjects());
                          break;
                        case 'delete':
                          onDelete(project);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: ListTile(
                          leading: Icon(Icons.edit),
                          title: Text('重命名'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'duplicate',
                        child: ListTile(
                          leading: Icon(Icons.copy),
                          title: Text('复制'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'export',
                        child: ListTile(
                          leading: Icon(Icons.ios_share),
                          title: Text('导出'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'exportBackup',
                        child: ListTile(
                          leading: Icon(Icons.backup),
                          title: Text('导出备份'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'grid',
                        child: ListTile(
                          leading: Icon(Icons.grid_view),
                          title: Text('字符总览'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline,
                              color: colorScheme.error),
                          title: Text('删除',
                              style: TextStyle(color: colorScheme.error)),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // 进度条（基于标准字表 108 字）
              if (standardTotal > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progress >= 1.0
                                ? Colors.green
                                : colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (progress >= 1.0) ...[
                      Icon(Icons.check_circle, size: 18, color: Colors.green),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      '$standardEdited/$standardTotal  ${(progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: progress >= 1.0
                            ? Colors.green
                            : colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 格式化日期
  String formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';

    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 构建带搜索高亮的项目名称
  Widget buildHighlightedName(String name, ColorScheme colorScheme, String searchQuery) {
    if (searchQuery.isEmpty) {
      return Text(
        name,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerName = name.toLowerCase();
    final lowerQuery = searchQuery.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = lowerName.indexOf(lowerQuery, start);
      if (index == -1) {
        // 剩余未匹配部分
        spans.add(TextSpan(
          text: name.substring(start),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ));
        break;
      }
      // 匹配前的部分
      if (index > start) {
        spans.add(TextSpan(
          text: name.substring(start, index),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ));
      }
      // 高亮匹配部分
      spans.add(TextSpan(
        text: name.substring(index, index + searchQuery.length),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: colorScheme.primary,
          backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.4),
        ),
      ));
      start = index + searchQuery.length;
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 获取项目统计信息（基于标准字表 108 字）
  (int totalChars, int editedChars, int standardTotal, int standardEdited, double progress)
      getProjectStats(FontProject project) {
    final totalChars = project.glyphs.length;
    final editedChars = project.glyphs.values
        .where((g) => g.contours.isNotEmpty)
        .length;

    // 标准字表进度：108 个标准字符中有多少已编辑
    final standardTotal = StandardCharset.allChars.length;
    int standardEdited = 0;
    for (final sc in StandardCharset.allChars) {
      final glyph = project.glyphs[sc.char];
      if (glyph != null && glyph.contours.isNotEmpty) {
        standardEdited++;
      }
    }
    final progress = standardTotal > 0 ? standardEdited / standardTotal : 0.0;
    return (totalChars, editedChars, standardTotal, standardEdited, progress);
  }

  /// 多选模式下的可选卡片
  Widget _buildSelectableCard({
    required FontProject project,
    required ColorScheme colorScheme,
    required bool isSelected,
    required VoidCallback onToggle,
    required void Function(FontProject) onOpen,
    required BuildContext context,
  }) {
    final stats = getProjectStats(project);
    final totalChars = stats.$1;
    final editedChars = stats.$2;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isSelected ? colorScheme.primaryContainer.withValues(alpha: 0.3) : null,
      child: InkWell(
        onTap: onToggle,
        onLongPress: () => onOpen(project),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // 选中状态
              Icon(
                isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
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
                    project.glyphs.isNotEmpty ? project.glyphs.keys.first : '字',
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

  /// 显示项目操作底部菜单
  void showProjectActions({
    required BuildContext context,
    required FontProject project,
    required Future<void> Function(FontProject) onRename,
    required Future<void> Function(FontProject) onDuplicate,
    required Future<void> Function(FontProject) onExport,
    required Future<void> Function(FontProject) onExportBackup,
    required Future<void> Function(FontProject) onDelete,
    required Future<void> Function() onLoadProjects,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部拖拽指示条
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 项目名称标题
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  project.name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // 重命名
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('重命名'),
                onTap: () {
                  Navigator.pop(ctx);
                  onRename(project);
                },
              ),
              // 复制
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('复制项目'),
                subtitle: const Text('创建项目副本'),
                onTap: () {
                  Navigator.pop(ctx);
                  onDuplicate(project);
                },
              ),
              // 导出
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('导出字体'),
                subtitle: const Text('导出为 TTF 文件'),
                onTap: () {
                  Navigator.pop(ctx);
                  onExport(project);
                },
              ),
              // 导出备份
              ListTile(
                leading: const Icon(Icons.backup),
                title: const Text('导出备份'),
                subtitle: const Text('导出 JSON 备份文件'),
                onTap: () {
                  Navigator.pop(ctx);
                  onExportBackup(project);
                },
              ),
              // 字符总览
              ListTile(
                leading: const Icon(Icons.grid_view),
                title: const Text('字符总览'),
                subtitle: const Text('查看造字进度'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    WFAnimations.slideRoute(CharacterGridScreen(project: project)),
                  ).then((_) => onLoadProjects());
                },
              ),
              // 删除（带危险样式）
              ListTile(
                leading: Icon(Icons.delete_outline, color: colorScheme.error),
                title: Text('删除项目',
                    style: TextStyle(color: colorScheme.error)),
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete(project);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
