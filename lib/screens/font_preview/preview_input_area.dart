import 'package:flutter/material.dart';

/// 文本输入区域组件
class PreviewInputArea extends StatelessWidget {
  final TextEditingController textController;
  final List<String> presets;

  const PreviewInputArea({
    super.key,
    required this.textController,
    required this.presets,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 多行文本输入框
          TextField(
            controller: textController,
            maxLines: 3,
            minLines: 1,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: '输入要预览的文字…',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              filled: true,
              fillColor: colorScheme.surface,
            ),
            onChanged: (_) {}, // 父组件通过 controller 监听
          ),
          const SizedBox(height: 4),

          // 提示文字
          Text(
            '输入文字预览字体效果',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),

          // 快捷预设按钮
          Wrap(
            spacing: 8,
            children: presets.map((preset) {
              final isSelected = textController.text == preset;
              return ActionChip(
                label: Text(
                  preset,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                backgroundColor: isSelected
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                onPressed: () {
                  textController.text = preset;
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
