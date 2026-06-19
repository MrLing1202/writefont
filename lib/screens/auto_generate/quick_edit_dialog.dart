import 'dart:typed_data';
import 'package:flutter/material.dart';

/// 快速修改字符对话框
/// 返回用户输入的新字符，取消返回 null
Future<String?> showQuickEditCharacterDialog(
  BuildContext context, {
  required Uint8List cellImage,
  required int index,
  required String currentChar,
}) {
  final controller = TextEditingController(text: currentChar);

  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final colorScheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.memory(cellImage, fit: BoxFit.contain, cacheWidth: 200, cacheHeight: 200),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('修改字符', style: TextStyle(fontSize: 18)),
                  Text(
                    '第 ${index + 1} 个字符',
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
        content: TextField(
          controller: controller,
          maxLength: 1,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '输入正确字符',
            hintText: '输入一个字符',
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onSubmitted: (v) {
            if (v.isNotEmpty) {
              Navigator.pop(ctx, v);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final val = controller.text;
              if (val.isNotEmpty) {
                Navigator.pop(ctx, val);
              }
            },
            child: const Text('确认'),
          ),
        ],
      );
    },
  );
}
