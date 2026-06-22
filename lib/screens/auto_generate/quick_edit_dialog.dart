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

/// AI 识别候选选择对话框
/// 展示 top-N 候选字符，用户点选或手动输入
/// 返回用户选择的字符，取消返回 null
Future<String?> showCandidateSelectionDialog(
  BuildContext context, {
  required Uint8List cellImage,
  required int index,
  required String currentChar,
  required List<String> candidates,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final colorScheme = Theme.of(ctx).colorScheme;
      return _CandidateDialog(
        cellImage: cellImage,
        index: index,
        currentChar: currentChar,
        candidates: candidates,
        colorScheme: colorScheme,
      );
    },
  );
}

class _CandidateDialog extends StatefulWidget {
  final Uint8List cellImage;
  final int index;
  final String currentChar;
  final List<String> candidates;
  final ColorScheme colorScheme;

  const _CandidateDialog({
    required this.cellImage,
    required this.index,
    required this.currentChar,
    required this.candidates,
    required this.colorScheme,
  });

  @override
  State<_CandidateDialog> createState() => _CandidateDialogState();
}

class _CandidateDialogState extends State<_CandidateDialog> {
  bool _showManualInput = false;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              border: Border.all(color: widget.colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.memory(widget.cellImage, fit: BoxFit.contain, cacheWidth: 200, cacheHeight: 200),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('选择字符', style: TextStyle(fontSize: 18)),
                Text(
                  '第 ${widget.index + 1} 个字符 · AI 识别候选',
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: _showManualInput ? _buildManualInput() : _buildCandidates(),
      actions: [
        if (!_showManualInput)
          TextButton(
            onPressed: () => setState(() => _showManualInput = true),
            child: const Text('手动输入'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _buildCandidates() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 当前识别结果提示
        Text(
          '当前: "$widget.currentChar"',
          style: TextStyle(
            fontSize: 13,
            color: widget.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        // 候选字符按钮
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: widget.candidates.map((c) {
            final isCurrent = c == widget.currentChar;
            return SizedBox(
              width: 72,
              height: 72,
              child: Material(
                color: isCurrent
                    ? widget.colorScheme.primaryContainer
                    : widget.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(context, c),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        c,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: isCurrent
                              ? widget.colorScheme.onPrimaryContainer
                              : widget.colorScheme.onSurface,
                        ),
                      ),
                      if (isCurrent)
                        Text(
                          '当前',
                          style: TextStyle(
                            fontSize: 10,
                            color: widget.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildManualInput() {
    return TextField(
      controller: _controller,
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
        if (v.isNotEmpty) Navigator.pop(context, v);
      },
    );
  }
}
