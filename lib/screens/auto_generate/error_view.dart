import 'package:flutter/material.dart';

/// 错误视图 — 显示错误信息和恢复操作按钮
class ErrorView extends StatelessWidget {
  final String status;
  final String? errorMessage;
  final bool hasRecognizedChars;
  final VoidCallback onReturnConfirm;
  final VoidCallback onReidentify;
  final VoidCallback onRetry;
  final VoidCallback onPop;
  final ColorScheme colorScheme;

  const ErrorView({
    super.key,
    required this.status,
    this.errorMessage,
    required this.hasRecognizedChars,
    required this.onReturnConfirm,
    required this.onReidentify,
    required this.onRetry,
    required this.onPop,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              status,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage ?? '未知错误',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // 有已识别字符时，优先显示"返回确认"按钮保留进度
            if (hasRecognizedChars) ...[
              FilledButton.icon(
                onPressed: onReturnConfirm,
                icon: const Icon(Icons.check_circle),
                label: const Text('返回确认'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onReidentify,
                icon: const Icon(Icons.refresh),
                label: const Text('全部重新识别'),
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onPop,
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }
}
