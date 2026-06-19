import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../data/standard_charset.dart';

/// 项目卡片 — 显示项目信息、统计和操作按钮
class ProjectCard extends StatelessWidget {
  final FontProject project;
  final ColorScheme colorScheme;
  final String searchQuery;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<String> onMenuAction;

  const ProjectCard({
    super.key,
    required this.project,
    required this.colorScheme,
    this.searchQuery = '',
    required this.onTap,
    required this.onLongPress,
    required this.onMenuAction,
  });

  /// 获取项目统计信息（基于标准字表 108 字）
  (int totalChars, int editedChars, int standardTotal, int standardEdited, double progress)
      _getProjectStats() {
    final totalChars = project.glyphs.length;
    final editedChars = project.glyphs.values
        .where((g) => g.contours.isNotEmpty)
        .length;

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

  /// 格式化日期
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';

    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 构建带搜索高亮的项目名称
  Widget _buildHighlightedName(String name) {
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

  @override
  Widget build(BuildContext context) {
    final stats = _getProjectStats();
    final totalChars = stats.$1;
    final editedChars = stats.$2;
    final standardTotal = stats.$3;
    final standardEdited = stats.$4;
    final progress = stats.$5;
    final createdStr = _formatDate(project.createdAt);
    final updatedStr = _formatDate(project.updatedAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
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
                        _buildHighlightedName(project.name),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.text_fields, size: 14, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              '$totalChars 个字符',
                              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.edit_note, size: 14, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Text(
                              '已编辑 $editedChars',
                              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.calendar_today, size: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                            const SizedBox(width: 4),
                            Text(
                              '创建于 $createdStr',
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.access_time, size: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                            const SizedBox(width: 4),
                            Text(
                              updatedStr,
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 操作按钮
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: colorScheme.onSurfaceVariant),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onSelected: onMenuAction,
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.edit), title: Text('重命名'), dense: true, contentPadding: EdgeInsets.zero)),
                      const PopupMenuItem(value: 'duplicate', child: ListTile(leading: Icon(Icons.copy), title: Text('复制'), dense: true, contentPadding: EdgeInsets.zero)),
                      const PopupMenuItem(value: 'export', child: ListTile(leading: Icon(Icons.ios_share), title: Text('导出'), dense: true, contentPadding: EdgeInsets.zero)),
                      const PopupMenuItem(value: 'exportBackup', child: ListTile(leading: Icon(Icons.backup), title: Text('导出备份'), dense: true, contentPadding: EdgeInsets.zero)),
                      const PopupMenuItem(value: 'grid', child: ListTile(leading: Icon(Icons.grid_view), title: Text('字符总览'), dense: true, contentPadding: EdgeInsets.zero)),
                      PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: colorScheme.error), title: Text('删除', style: TextStyle(color: colorScheme.error)), dense: true, contentPadding: EdgeInsets.zero)),
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
                            progress >= 1.0 ? Colors.green : colorScheme.primary,
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
                        color: progress >= 1.0 ? Colors.green : colorScheme.primary,
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
}
