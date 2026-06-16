import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '手迹造字',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  'WriteFont',
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero card
                  Card(
                    elevation: 0,
                    color: colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.edit_note,
                            size: 48,
                            color: colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '创建你的手写字体',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '拍照或选择手写字符图片，调节参数，生成属于你的个性化 TTF 字体',
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer.withOpacity(0.8),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Steps section
                  Text(
                    '使用步骤',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  _StepCard(
                    icon: Icons.camera_alt_outlined,
                    step: '1',
                    title: '拍照 / 选图',
                    description: '拍摄手写字符照片，或从相册选择图片。建议使用方格纸书写。',
                    color: colorScheme,
                  ),
                  const SizedBox(height: 12),
                  _StepCard(
                    icon: Icons.tune,
                    step: '2',
                    title: '调节参数',
                    description: '调整阈值、笔画粗细、平滑度等参数，优化字符识别效果。',
                    color: colorScheme,
                  ),
                  const SizedBox(height: 12),
                  _StepCard(
                    icon: Icons.preview,
                    step: '3',
                    title: '预览字体',
                    description: '实时预览生成的字体效果，输入任意文字查看显示效果。',
                    color: colorScheme,
                  ),
                  const SizedBox(height: 12),
                  _StepCard(
                    icon: Icons.file_download_outlined,
                    step: '4',
                    title: '导出 TTF',
                    description: '导出标准 TTF 字体文件，可安装到手机或电脑使用。',
                    color: colorScheme,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).pushNamed('/capture');
        },
        icon: const Icon(Icons.add),
        label: const Text('开始造字'),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final IconData icon;
  final String step;
  final String title;
  final String description;
  final ColorScheme color;

  const _StepCard({
    required this.icon,
    required this.step,
    required this.title,
    required this.description,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: color.outlineVariant,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: color.onSecondaryContainer,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: color.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
