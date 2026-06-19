import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 错误视图 — 显示错误信息和恢复操作按钮
class ErrorView extends StatefulWidget {
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
  State<ErrorView> createState() => _ErrorViewState();
}

class _ErrorViewState extends State<ErrorView> {
  int _retryCount = 0;

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
              color: widget.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              widget.status,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: widget.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.errorMessage ?? '未知错误',
              style: TextStyle(
                fontSize: 14,
                color: widget.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (_retryCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '已重试 $_retryCount 次',
                style: TextStyle(
                  fontSize: 12,
                  color: widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ],
            const SizedBox(height: 32),

            // 有已识别字符时，优先显示"返回确认"按钮保留进度
            if (widget.hasRecognizedChars) ...[
              FilledButton.icon(
                onPressed: widget.onReturnConfirm,
                icon: const Icon(Icons.check_circle),
                label: const Text('返回确认'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _retryCount++);
                  widget.onReidentify();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('全部重新识别'),
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: () {
                  setState(() => _retryCount++);
                  widget.onRetry();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
            const SizedBox(height: 12),
            // 复制错误信息按钮
            OutlinedButton.icon(
              onPressed: () {
                final errorText = '${widget.status}\n${widget.errorMessage ?? ''}';
                Clipboard.setData(ClipboardData(text: errorText));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('错误信息已复制'), duration: Duration(seconds: 2)),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('复制错误信息'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: widget.onPop,
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }
}
