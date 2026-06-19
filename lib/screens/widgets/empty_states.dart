import 'package:flutter/material.dart';

/// 空状态提示（无项目时）
class EmptyProjectState extends StatelessWidget {
  final VoidCallback onCreateProject;

  const EmptyProjectState({super.key, required this.onCreateProject});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
}

/// 搜索无结果提示
class SearchEmptyState extends StatelessWidget {
  const SearchEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
}
