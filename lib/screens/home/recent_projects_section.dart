import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../theme/app_theme.dart';
import '../character_grid_screen.dart';

/// 最近项目区域组件
class RecentProjectsSection extends StatelessWidget {
  final List<FontProject> recentProjects;

  const RecentProjectsSection({
    super.key,
    required this.recentProjects,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            children: [
              Icon(Icons.history, size: 18, color: WFColors.textSecondaryColor(context)),
              const SizedBox(width: 8),
              Text(
                '最近项目',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textSecondaryColor(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 项目卡片列表
        ...recentProjects.map((project) => _RecentProjectCard(project: project)),
      ],
    );
  }
}

class _RecentProjectCard extends StatelessWidget {
  final FontProject project;

  const _RecentProjectCard({required this.project});

  @override
  Widget build(BuildContext context) {
    final glyphCount = project.glyphs.length;
    final diff = DateTime.now().difference(project.updatedAt);
    String timeDesc;
    if (diff.inMinutes < 1) {
      timeDesc = '刚刚';
    } else if (diff.inHours < 1) {
      timeDesc = '${diff.inMinutes} 分钟前';
    } else if (diff.inDays < 1) {
      timeDesc = '${diff.inHours} 小时前';
    } else if (diff.inDays < 30) {
      timeDesc = '${diff.inDays} 天前';
    } else {
      timeDesc = '${project.updatedAt.month}/${project.updatedAt.day}';
    }

    return WFCard(
      onTap: () {
        Navigator.push(
          context,
          WFAnimations.slideRoute(CharacterGridScreen(project: project)),
        );
      },
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: WFColors.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.font_download, size: 22, color: WFColors.info),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: WFColors.textPrimaryColor(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$glyphCount 个字符 · $timeDesc',
                  style: TextStyle(
                    fontSize: 12,
                    color: WFColors.textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: WFColors.textLightColor(context)),
        ],
      ),
    );
  }
}
