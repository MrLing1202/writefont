import 'dart:async';
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/stroke_order_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/bezier_glyph_painter.dart';

/// 笔画顺序演示页面
class StrokeOrderScreen extends StatefulWidget {
  final FontProject project;
  const StrokeOrderScreen({super.key, required this.project});

  @override
  State<StrokeOrderScreen> createState() => _StrokeOrderScreenState();
}

class _StrokeOrderScreenState extends State<StrokeOrderScreen>
    with SingleTickerProviderStateMixin {
  String _selectedChar = '';
  List<Contour> _strokes = [];
  int _currentStroke = -1;
  bool _isPlaying = false;
  Timer? _timer;
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    final chars = widget.project.glyphs.keys.toList();
    if (chars.isNotEmpty) {
      _selectChar(chars.first);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _selectChar(String char) {
    _timer?.cancel();
    final glyph = widget.project.glyphs[char];
    if (glyph == null) return;
    setState(() {
      _selectedChar = char;
      _strokes = StrokeOrderService.extractStrokeOrder(glyph);
      _currentStroke = -1;
      _isPlaying = false;
    });
  }

  void _play() {
    if (_strokes.isEmpty) return;
    setState(() {
      _isPlaying = true;
      _currentStroke = 0;
    });
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(milliseconds: (800 / _speed).round()),
      (_) {
        if (_currentStroke < _strokes.length - 1) {
          setState(() => _currentStroke++);
        } else {
          _timer?.cancel();
          setState(() => _isPlaying = false);
        }
      },
    );
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _isPlaying = false);
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _currentStroke = -1;
      _isPlaying = false;
    });
  }

  void _stepForward() {
    if (_currentStroke < _strokes.length - 1) {
      setState(() => _currentStroke++);
    }
  }

  void _stepBackward() {
    if (_currentStroke > 0) {
      setState(() => _currentStroke--);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WFAppBar(title: '笔画顺序'),
      body: Column(
        children: [
          _buildCharSelector(),
          const Divider(height: 1),
          Expanded(child: _buildStrokeCanvas()),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildCharSelector() {
    final chars = widget.project.glyphs.keys.toList();
    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: chars.length,
        itemBuilder: (ctx, i) {
          final char = chars[i];
          final isSelected = char == _selectedChar;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(char, style: const TextStyle(fontSize: 18)),
              selected: isSelected,
              onSelected: (_) => _selectChar(char),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStrokeCanvas() {
    if (_selectedChar.isEmpty || _strokes.isEmpty) {
      return const Center(child: Text('暂无笔画数据'));
    }

    return LayoutBuilder(
      builder: (ctx, constraints) {
        return Container(
          color: Theme.of(context).colorScheme.surface,
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _StrokeOrderPainter(
              strokes: _strokes,
              currentStroke: _currentStroke,
              char: _selectedChar,
              colorScheme: Theme.of(context).colorScheme,
            ),
          ),
        );
      },
    );
  }

  Widget _buildControls() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度条
            Row(
              children: [
                Text(
                  _currentStroke < 0
                      ? '准备'
                      : '第 ${_currentStroke + 1}/${_strokes.length} 笔',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Slider(
                    value: (_currentStroke + 1).toDouble(),
                    min: 0,
                    max: _strokes.length.toDouble(),
                    divisions: _strokes.length,
                    onChanged: _isPlaying
                        ? null
                        : (v) => setState(() => _currentStroke = v.round() - 1),
                  ),
                ),
              ],
            ),
            // 速度控制
            Row(
              children: [
                const Text('速度', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _speed,
                    min: 0.5,
                    max: 3.0,
                    divisions: 5,
                    label: '${_speed.toStringAsFixed(1)}x',
                    onChanged: (v) {
                      setState(() => _speed = v);
                      if (_isPlaying) {
                        _timer?.cancel();
                        _timer = Timer.periodic(
                          Duration(milliseconds: (800 / _speed).round()),
                          (_) {
                            if (_currentStroke < _strokes.length - 1) {
                              setState(() => _currentStroke++);
                            } else {
                              _timer?.cancel();
                              setState(() => _isPlaying = false);
                            }
                          },
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
            // 控制按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: _stepBackward,
                ),
                IconButton(
                  icon: const Icon(Icons.replay),
                  onPressed: _reset,
                ),
                IconButton(
                  iconSize: 48,
                  icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle),
                  onPressed: _isPlaying ? _pause : _play,
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: _stepForward,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 笔画顺序绘制器
class _StrokeOrderPainter extends CustomPainter {
  final List<Contour> strokes;
  final int currentStroke;
  final String char;
  final ColorScheme colorScheme;

  _StrokeOrderPainter({
    required this.strokes,
    required this.currentStroke,
    required this.char,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;

    // 计算字形边界
    int minX = 99999, minY = 99999, maxX = -99999, maxY = -99999;
    for (final s in strokes) {
      for (final p in s.points) {
        if (p.x < minX) minX = p.x;
        if (p.y < minY) minY = p.y;
        if (p.x > maxX) maxX = p.x;
        if (p.y > maxY) maxY = p.y;
      }
    }

    final glyphW = (maxX - minX).toDouble().clamp(1, 99999);
    final glyphH = (maxY - minY).toDouble().clamp(1, 99999);
    final scale = (size.width * 0.7) / glyphW;
    final offsetX = (size.width - glyphW * scale) / 2 - minX * scale;
    final offsetY = (size.height - glyphH * scale) / 2 - minY * scale;

    // 绘制已完成的笔画（黑色）
    for (int i = 0; i <= currentStroke && i < strokes.length; i++) {
      _drawStroke(canvas, strokes[i], offsetX, offsetY, scale,
          i == currentStroke ? colorScheme.primary : colorScheme.onSurface,
          strokeWidth: i == currentStroke ? 4.0 : 3.0);
    }

    // 绘制未完成的笔画（灰色虚线）
    for (int i = currentStroke + 1; i < strokes.length; i++) {
      _drawStroke(canvas, strokes[i], offsetX, offsetY, scale,
          colorScheme.outlineVariant,
          strokeWidth: 1.5, dashed: true);
    }

    // 当前笔画序号标注
    if (currentStroke >= 0 && currentStroke < strokes.length) {
      final firstPoint = strokes[currentStroke].points.first;
      final dx = firstPoint.x * scale + offsetX;
      final dy = firstPoint.y * scale + offsetY;
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${currentStroke + 1}',
          style: TextStyle(
            color: colorScheme.primary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(dx - 8, dy - 20));
    }
  }

  void _drawStroke(Canvas canvas, Contour stroke, double offsetX, double offsetY,
      double scale, Color color,
      {double strokeWidth = 3.0, bool dashed = false}) {
    if (stroke.points.length < 2) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final first = stroke.points.first;
    path.moveTo(first.x * scale + offsetX, first.y * scale + offsetY);

    for (int i = 1; i < stroke.points.length; i++) {
      final p = stroke.points[i];
      path.lineTo(p.x * scale + offsetX, p.y * scale + offsetY);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _StrokeOrderPainter oldDelegate) {
    return oldDelegate.currentStroke != currentStroke ||
        oldDelegate.char != char;
  }
}
