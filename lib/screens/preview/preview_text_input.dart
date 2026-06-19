import 'package:flutter/material.dart';

/// 预览文字输入框
class PreviewTextInput extends StatelessWidget {
  final TextEditingController textController;
  final String previewText;
  final ValueChanged<String> onChanged;

  const PreviewTextInput({
    super.key,
    required this.textController,
    required this.previewText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        controller: textController,
        decoration: InputDecoration(
          labelText: '预览文字',
          hintText: '输入要预览的文字',
          prefixIcon: const Icon(Icons.text_fields),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          suffixIcon: IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              textController.clear();
              onChanged('');
            },
          ),
        ),
        onChanged: onChanged,
        maxLines: 2,
      ),
    );
  }
}
