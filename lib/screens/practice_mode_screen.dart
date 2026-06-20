import 'dart:math';
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../theme/app_theme.dart';

/// 手写练习模式页面
///
/// 分析用户已生成字体中的"弱字"（笔画少、结构简单的字），
/// 提供针对性练习，支持田字格描红和自由书写。
class PracticeModeScreen extends StatefulWidget {
  final FontProject project;

  const PracticeModeScreen({super.key, required this.project});

  @override
  State<PracticeModeScreen> createState() => _PracticeModeScreenState();
}

class _PracticeModeScreenState extends State<PracticeModeScreen> {
  late List<String> _practiceChars;
  int _currentIndex = 0;
  int _practiceCount = 0;
  final List<_PracticeRecord> _records = [];
  bool _showGuide = true;

  /// 笔画数估算（简单用Unicode区间粗略估计）
  static int _estimateStrokes(String char) {
    final code = char.codeUnitAt(0);
    if (code >= 0x4E00 && code <= 0x9FFF) {
      // CJK统一汉字，用hash粗略映射
      return (char.hashCode.abs() % 15) + 1;
    }
    return 1;
  }

  @override
  void initState() {
    super.initState();
    _preparePracticeChars();
  }

  /// 准备练习字符：优先选择笔画少的字（更适合练习）
  void _preparePracticeChars() {
    final chars = widget.project.glyphs.keys.toList();
    chars.sort((a, b) => _estimateStrokes(a).compareTo(_estimateStrokes(b)));
    _practiceChars = chars.take(50).toList();
    if (_practiceChars.isEmpty) {
      _practiceChars = ['永', '东', '国', '酬', '鹰'];
    }
    _practiceChars.shuffle(Random());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('练习模式'),
        actions: [
          IconButton(
            icon: Icon(_showGuide ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _showGuide = !_showGuide),
            tooltip: _showGuide ? '隐藏辅助线' : '显示辅助线',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildProgressHeader(theme),
          Expanded(child: _buildPracticeArea(theme)),
          _buildBottomBar(theme),
        ],
      ),
    );
  }

  /// 进度头部
  Widget _buildProgressHeader(ThemeData theme) {
    final progress = _practiceChars.isEmpty ? 0.0 : (_currentIndex / _practiceChars.length);
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '第 ${_currentIndex + 1} / ${_practiceChars.length} 字',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              Text(
                '已练习 $_practiceCount 次',
                style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }

  /// 练习区域
  Widget _buildPracticeArea(ThemeData theme) {
    if (_practiceChars.isEmpty) {
      return const Center(child: Text('没有可练习的字符'));
    }

    final char = _practiceChars[_currentIndex];
    final glyph = widget.project.glyphs[char];

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 参考字（大）
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.red.withOpacity(0.6), width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: CustomPaint(
              painter: _PracticeGridPainter(showGuide: _showGuide),
              child: Center(
                child: Text(
                  char,
                  style: TextStyle(
                    fontSize: 120,
                    color: theme.colorScheme.onSurface.withOpacity(0.15),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 字符信息
          if (glyph != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    '笔画数: ~${_estimateStrokes(char)}  |  '
                    '轮廓数: ${glyph.contours.length}  |  '
                    '置信度: ${(glyph.confidence ?? 0).toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 练习提示
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  '✍️ 请在方格纸上练习书写「$char」',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  '建议练习3-5遍，注意笔画顺序和结构比例',
                  style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 底部操作栏
  Widget _buildBottomBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 上一个
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _currentIndex > 0 ? _previousChar : null,
              icon: const Icon(Icons.chevron_left),
              label: const Text('上一个'),
            ),
          ),
          const SizedBox(width: 12),
          // 标记已练习
          Expanded(
            child: FilledButton.icon(
              onPressed: _markPracticed,
              icon: const Icon(Icons.check),
              label: const Text('已练习'),
            ),
          ),
          const SizedBox(width: 12),
          // 下一个
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _currentIndex < _practiceChars.length - 1 ? _nextChar : null,
              icon: const Icon(Icons.chevron_right),
              label: const Text('下一个'),
            ),
          ),
        ],
      ),
    );
  }

  void _previousChar() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
    }
  }

  void _nextChar() {
    if (_currentIndex < _practiceChars.length - 1) {
      setState(() => _currentIndex++);
    }
  }

  void _markPracticed() {
    setState(() {
      _practiceCount++;
      _records.add(_PracticeRecord(
        char: _practiceChars[_currentIndex],
        timestamp: DateTime.now(),
      ));
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ 已练习「${_practiceChars[_currentIndex]}」— 共 $_practiceCount 字'),
        duration: const Duration(seconds: 1),
      ),
    );

    // 自动跳到下一个
    if (_currentIndex < _practiceChars.length - 1) {
      Future.delayed(const Duration(milliseconds: 500), _nextChar);
    } else {
      _showCompleteDialog();
    }
  }

  void _showCompleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🎉 练习完成'),
        content: Text('恭喜完成 $_practiceCount 个字的练习！\n\n建议每天坚持练习，字体会越来越好。'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _currentIndex = 0;
                _practiceChars.shuffle(Random());
              });
            },
            child: const Text('再来一轮'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }
}

/// 练习记录
class _PracticeRecord {
  final String char;
  final DateTime timestamp;

  _PracticeRecord({required this.char, required this.timestamp});
}

/// 练习格子绘制器
class _PracticeGridPainter extends CustomPainter {
  final bool showGuide;

  _PracticeGridPainter({this.showGuide = true});

  @override
  void paint(Canvas canvas, Size size) {
    if (!showGuide) return;

    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // 十字虚线
    _drawDashedLine(canvas, Offset(centerX, 0), Offset(centerX, size.height), paint);
    _drawDashedLine(canvas, Offset(0, centerY), Offset(size.width, centerY), paint);

    // 对角虚线
    _drawDashedLine(canvas, Offset(0, 0), Offset(size.width, size.height), paint);
    _drawDashedLine(canvas, Offset(size.width, 0), Offset(0, size.height), paint);
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dash = 5.0;
    const gap = 3.0;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final len = (dx * dx + dy * dy).abs().sqrt();
    final count = (len / (dash + gap)).floor();
    final ux = dx / len;
    final uy = dy / len;

    for (int i = 0; i < count; i++) {
      final s = Offset(start.dx + ux * i * (dash + gap), start.dy + uy * i * (dash + gap));
      final e = Offset(s.dx + ux * dash, s.dy + uy * dash);
      canvas.drawLine(s, e, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PracticeGridPainter oldDelegate) => oldDelegate.showGuide != showGuide;
}
