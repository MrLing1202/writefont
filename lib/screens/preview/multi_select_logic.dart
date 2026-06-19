import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 构建多选模式的 AppBar
PreferredSizeWidget buildMultiSelectAppBar({
  required int selectedCount,
  required VoidCallback onExit,
  required VoidCallback onDelete,
}) {
  return WFAppBar(
    title: '已选 $selectedCount 个',
    leading: IconButton(
      onPressed: onExit,
      icon: const Icon(Icons.close),
    ),
    actions: [
      IconButton(
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline, color: WFColors.error),
        tooltip: '删除选中',
      ),
    ],
  );
}

/// 显示删除确认对话框，返回是否确认
Future<bool> showDeleteConfirmDialog(BuildContext context, int count) async {
  final confirmed = await WFDialog.show<bool>(
    context,
    title: '确认删除',
    content: Text('确定要删除选中的 $count 个字符吗？此操作不可撤销。'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, true),
        style: TextButton.styleFrom(foregroundColor: WFColors.error),
        child: const Text('删除'),
      ),
    ],
  );
  return confirmed == true;
}
