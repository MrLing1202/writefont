import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 欢迎区域头部组件（渐变背景 + 统计数据）
class WelcomeHeader extends StatelessWidget {
  final int savedProjectCount;
  final int totalCharCount;
  final String lastActivityDesc;

  const WelcomeHeader({
    super.key,
    required this.savedProjectCount,
    required this.totalCharCount,
    required this.lastActivityDesc,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [WFColors.primary, WFColors.primaryLight],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: WFColors.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // 图标
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.font_download,
              size: 36,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '欢迎使用手迹造字',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '拍照生成你的专属手写字体',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 20),
          // 统计栏
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem('$savedProjectCount', '已创建项目'),
              Container(
                width: 1,
                height: 32,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              _buildStatItem('$totalCharCount', '已识别字符'),
              Container(
                width: 1,
                height: 32,
                color: Colors.white.withValues(alpha: 0.2),
              ),
              _buildStatItem(
                lastActivityDesc.isNotEmpty ? lastActivityDesc : '-',
                '最近活动',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
