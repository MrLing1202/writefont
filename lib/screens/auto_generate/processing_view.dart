import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// 处理中的视图 — 图片预览 + 进度指示器 + 状态文字 + 预估时间 + 取消
class ProcessingView extends StatefulWidget {
  final Uint8List imageBytes;
  final double progress;
  final String status;
  final ColorScheme colorScheme;
  final VoidCallback? onCancel;

  const ProcessingView({
    super.key,
    required this.imageBytes,
    required this.progress,
    required this.status,
    required this.colorScheme,
    this.onCancel,
  });

  @override
  State<ProcessingView> createState() => _ProcessingViewState();
}

class _ProcessingViewState extends State<ProcessingView> {
  late final Stopwatch _stopwatch;
  Timer? _timer;
  String _elapsedText = '';
  String _remainingText = '';

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  void _updateTime() {
    if (!mounted) return;
    final elapsed = _stopwatch.elapsed;
    final elapsedSec = elapsed.inSeconds;
    setState(() {
      _elapsedText = _formatDuration(elapsedSec);
      // 根据当前进度估算剩余时间
      if (widget.progress > 0.05 && widget.progress < 1.0) {
        final estimatedTotal = elapsedSec / widget.progress;
        final remaining = (estimatedTotal - elapsedSec).round();
        _remainingText = remaining > 0 ? '预计剩余 ${_formatDuration(remaining)}' : '即将完成';
      } else {
        _remainingText = '';
      }
    });
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}秒';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}分${s > 0 ? '${s}秒' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 图片预览
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.colorScheme.outlineVariant,
                  width: 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.memory(
                widget.imageBytes,
                fit: BoxFit.cover,
                cacheWidth: 800,
                cacheHeight: 800,
              ),
            ),
            const SizedBox(height: 40),

            // 进度指示器
            SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                value: widget.progress < 1.0 ? widget.progress : null,
                strokeWidth: 4,
                color: widget.colorScheme.primary,
                backgroundColor: widget.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 24),

            // 进度条
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: widget.progress,
                minHeight: 8,
                color: widget.colorScheme.primary,
                backgroundColor: widget.colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 16),

            // 状态文字
            Text(
              widget.status,
              style: TextStyle(
                fontSize: 16,
                color: widget.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),

            // 时间信息
            if (_elapsedText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '已用时 $_elapsedText${_remainingText.isNotEmpty ? ' · $_remainingText' : ''}',
                style: TextStyle(
                  fontSize: 13,
                  color: widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],

            // 取消按钮
            if (widget.onCancel != null) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('取消'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: widget.colorScheme.error,
                  side: BorderSide(color: widget.colorScheme.error.withValues(alpha: 0.5)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
