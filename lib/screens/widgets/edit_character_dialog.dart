import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../processing_screen.dart';

/// 弹出编辑对话框（带图片预览） — 用于修正识别结果
class EditCharacterDialog extends StatefulWidget {
  final int index;
  final Uint8List imageBytes;
  final String? currentChar;
  final ConfidenceLevel confidence;
  final ValueChanged<String> onConfirm;
  final VoidCallback? onMarkCorrect;

  const EditCharacterDialog({
    super.key,
    required this.index,
    required this.imageBytes,
    this.currentChar,
    required this.confidence,
    required this.onConfirm,
    this.onMarkCorrect,
  });

  @override
  State<EditCharacterDialog> createState() => _EditCharacterDialogState();
}

class _EditCharacterDialogState extends State<EditCharacterDialog> {
  TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.currentChar ?? '';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final confidence = widget.confidence;

    return AlertDialog(
      title: Row(
        children: [
          const Text('修正字符'),
          const Spacer(),
          // 置信度指示
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: confidence == ConfidenceLevel.high
                  ? Colors.green.withValues(alpha: 0.1)
                  : confidence == ConfidenceLevel.medium
                      ? Colors.orange.withValues(alpha: 0.1)
                      : Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: confidence == ConfidenceLevel.high
                    ? Colors.green
                    : confidence == ConfidenceLevel.medium
                        ? Colors.orange
                        : Colors.red,
              ),
            ),
            child: Text(
              confidence == ConfidenceLevel.high
                  ? '高置信'
                  : confidence == ConfidenceLevel.medium
                      ? '中置信'
                      : '低置信',
              style: TextStyle(
                fontSize: 12,
                color: confidence == ConfidenceLevel.high
                    ? Colors.green
                    : confidence == ConfidenceLevel.medium
                        ? Colors.orange
                        : Colors.red,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 原始裁切图片
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                widget.imageBytes,
                fit: BoxFit.contain,
                cacheWidth: 200,
                cacheHeight: 200,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 编辑输入框
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              labelText: '识别结果',
              hintText: '输入对应字符',
              border: const OutlineInputBorder(),
              counterText: '',
            ),
          ),
        ],
      ),
      actions: [
        // 跳过按钮
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('跳过'),
        ),
        // 正确按钮（确认当前识别结果）
        if (widget.currentChar != null)
          FilledButton.tonal(
            onPressed: () {
              widget.onMarkCorrect?.call();
              Navigator.pop(context);
            },
            child: const Text('正确'),
          ),
        // 确认修正
        FilledButton(
          onPressed: () {
            final text = _controller.text.trim();
            if (text.isNotEmpty) {
              widget.onConfirm(text);
            }
            Navigator.pop(context);
          },
          child: const Text('确认'),
        ),
      ],
    );
  }
}
