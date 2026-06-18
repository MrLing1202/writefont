import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../data/standard_charset.dart';
import '../models/project.dart';
import '../services/storage_service.dart';

/// 画笔工具模式
enum DrawTool {
  pencil, // 铅笔
  eraser, // 橡皮擦
}

/// 笔画记录（用于撤销/重做）
class StrokeRecord {
  final List<Offset> points;
  final double strokeWidth;
  final Color color;

  StrokeRecord({
    required this.points,
    required this.strokeWidth,
    required this.color,
  });
}

/// 画布绘制器 - 绘制所有笔画
class _CanvasPainter extends CustomPainter {
  final List<StrokeRecord> strokes;
  final StrokeRecord? activeStroke;
  final Offset? eraserPosition;
  final double eraserRadius;

  _CanvasPainter({
    required this.strokes,
    this.activeStroke,
    this.eraserPosition,
    this.eraserRadius = 10.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制所有已完成的笔画
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }
    // 绘制当前活动笔画
    if (activeStroke != null) {
      _drawStroke(canvas, activeStroke!);
    }
    // 绘制橡皮擦光标
    if (eraserPosition != null) {
      final fillPaint = Paint()
        ..color = Colors.red.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(eraserPosition!, eraserRadius, fillPaint);
      final borderPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(eraserPosition!, eraserRadius, borderPaint);
    }
  }

  /// 绘制单个笔画
  void _drawStroke(Canvas canvas, StrokeRecord stroke) {
    if (stroke.points.isEmpty) return;
    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (stroke.points.length == 1) {
      // 单点绘制为圆点
      final dotPaint = Paint()
        ..color = stroke.color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(stroke.points.first, stroke.strokeWidth / 2, dotPaint);
    } else {
      final path = Path();
      path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (int i = 1; i < stroke.points.length; i++) {
        final p0 = stroke.points[i - 1];
        final p1 = stroke.points[i];
        final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
        path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
      }
      final last = stroke.points.last;
      path.lineTo(last.dx, last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) => true;
}

/// 米字格绘制器（十字线 + 对角线）
class _GridPainter extends CustomPainter {
  final Color gridColor;

  _GridPainter({required this.gridColor});

  @override
  void paint(Canvas canvas, Size size) {
    final crossPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.8;

    // 水平中线
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      crossPaint,
    );
    // 垂直中线
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      crossPaint,
    );

    // 对角线
    final diagPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    // 左上 → 右下
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), diagPaint);
    // 右上 → 左下
    canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), diagPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 字符编辑对话框：支持画笔绘制、橡皮擦、撤销重做、缩放平移
class CharacterEditDialog extends StatefulWidget {
  final String character;
  final GlyphData glyph;
  final String? projectId;
  final VoidCallback onCharacterChanged;
  final VoidCallback onCharacterDeleted;

  const CharacterEditDialog({
    super.key,
    required this.character,
    required this.glyph,
    this.projectId,
    required this.onCharacterChanged,
    required this.onCharacterDeleted,
  });

  /// 显示编辑对话框的静态方法
  static Future<void> show(
    BuildContext context, {
    required String character,
    required GlyphData glyph,
    String? projectId,
    required VoidCallback onCharacterChanged,
    required VoidCallback onCharacterDeleted,
  }) {
    return showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => CharacterEditDialog(
        character: character,
        glyph: glyph,
        projectId: projectId,
        onCharacterChanged: onCharacterChanged,
        onCharacterDeleted: onCharacterDeleted,
      ),
    );
  }

  @override
  State<CharacterEditDialog> createState() => _CharacterEditDialogState();
}

class _CharacterEditDialogState extends State<CharacterEditDialog> {
  late TextEditingController _charController;
  String _selectedCharacter = '';
  Uint8List? _sourceImage;
  bool _isLoadingImage = false;

  // === 自动保存 ===
  static const Duration _autoSaveInterval = Duration(seconds: 30);
  Timer? _autoSaveTimer;

  // === 绘画相关状态 ===
  /// 当前工具模式
  DrawTool _currentTool = DrawTool.pencil;

  /// 已完成的笔画列表
  final List<StrokeRecord> _strokes = [];

  /// 当前正在绘制的笔画
  StrokeRecord? _activeStroke;

  /// 橡皮擦当前位置（用于显示光标）
  Offset? _eraserPosition;

  /// 笔画宽度（1-10像素）
  double _strokeWidth = 3.0;

  /// 画笔颜色
  final Color _penColor = Colors.black;

  /// 米字格辅助线开关
  bool _showGrid = true;

  /// 原始手写参考图显示开关
  bool _showSourceImage = false;

  /// 橡皮擦半径（10-50px，独立可调）
  double _eraserRadius = 20.0;

  // === 缩放/平移 ===
  final TransformationController _transformController =
      TransformationController();

  // === 撤销/重做 ===
  static const int _maxHistorySize = 30;
  final List<List<StrokeRecord>> _undoStack = [];
  final List<List<StrokeRecord>> _redoStack = [];

  // === 画布尺寸 ===
  static const double _canvasSize = 500.0;

  @override
  void initState() {
    super.initState();
    _selectedCharacter = widget.character;
    _charController = TextEditingController(text: widget.character);
    _loadSourceImage();
    _loadContoursToStrokes();
    // 启动30秒自动保存定时器
    _autoSaveTimer = Timer.periodic(_autoSaveInterval, (_) => _autoSave());
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    // 退出前执行最后一次保存
    _autoSave();
    _charController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  /// 自动保存：将当前笔画同步到 GlyphData 轮廓
  void _autoSave() {
    if (_strokes.isEmpty) return;
    _saveStrokesToContours();
    debugPrint('自动保存: 已保存 ${_strokes.length} 个笔画到轮廓');
  }

  /// 从 GlyphData 轮廓加载已有笔画
  void _loadContoursToStrokes() {
    for (final contour in widget.glyph.contours) {
      if (contour.points.isEmpty) continue;
      final points = contour.points
          .map((p) => Offset(p.x.toDouble(), p.y.toDouble()))
          .toList();
      _strokes.add(StrokeRecord(
        points: points,
        strokeWidth: _strokeWidth,
        color: _penColor,
      ));
    }
  }

  /// 将当前笔画保存到 GlyphData 轮廓
  void _saveStrokesToContours() {
    widget.glyph.contours.clear();
    for (final stroke in _strokes) {
      if (stroke.points.isEmpty) continue;
      final contourPoints = stroke.points
          .map((p) => ContourPoint(p.dx.round(), p.dy.round()))
          .toList();
      widget.glyph.contours.add(Contour(contourPoints));
    }
    // 重新计算字宽
    widget.glyph.advanceWidth = widget.glyph.calculateAdvanceWidth();
  }

  /// 加载字符的原始图片
  Future<void> _loadSourceImage() async {
    if (widget.projectId == null) return;
    setState(() => _isLoadingImage = true);
    try {
      final image = await StorageService.loadCharacterImage(
        widget.projectId!,
        widget.character,
      );
      if (mounted) {
        setState(() {
          _sourceImage = image;
          _isLoadingImage = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingImage = false);
    }
  }

  /// 修改字符标签
  void _changeCharacter(String newChar) {
    if (newChar.isEmpty || newChar == widget.character) return;
    setState(() {
      _selectedCharacter = newChar;
      _charController.text = newChar;
    });
  }

  /// 确认修改并退出
  void _confirmEdit() {
    // 保存笔画到轮廓
    _saveStrokesToContours();
    if (_selectedCharacter != widget.character &&
        _selectedCharacter.isNotEmpty) {
      widget.glyph.character = _selectedCharacter;
      widget.glyph.unicode = _selectedCharacter.codeUnitAt(0);
    }
    widget.onCharacterChanged();
    Navigator.pop(context);
  }

  /// 删除字符
  void _deleteCharacter() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(ctx).colorScheme.error,
          size: 48,
        ),
        title: const Text('删除字符'),
        content: Text('确定要删除字符「${widget.character}」吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx); // 关闭确认对话框
              Navigator.pop(context); // 关闭编辑对话框
              widget.onCharacterDeleted();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // === 撤销/重做 ===

  /// 保存当前状态到撤销栈
  void _pushUndo() {
    _undoStack.add(List<StrokeRecord>.from(_strokes));
    if (_undoStack.length > _maxHistorySize) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// 撤销
  void _undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(List<StrokeRecord>.from(_strokes));
    final previous = _undoStack.removeLast();
    setState(() {
      _strokes.clear();
      _strokes.addAll(previous);
    });
  }

  /// 重做
  void _redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(List<StrokeRecord>.from(_strokes));
    final next = _redoStack.removeLast();
    setState(() {
      _strokes.clear();
      _strokes.addAll(next);
    });
  }

  /// 清除所有笔画
  void _clearAll() {
    if (_strokes.isEmpty) return;
    _pushUndo();
    setState(() {
      _strokes.clear();
      _eraserPosition = null;
    });
  }

  /// 适应屏幕 - 重置视图
  void _fitToScreen() {
    setState(() {
      _transformController.value = Matrix4.identity();
    });
  }

  /// 放大
  void _zoomIn() {
    final matrix = _transformController.value.clone();
    matrix.scale(1.2);
    setState(() {
      _transformController.value = matrix;
    });
  }

  /// 缩小
  void _zoomOut() {
    final matrix = _transformController.value.clone();
    matrix.scale(1 / 1.2);
    setState(() {
      _transformController.value = matrix;
    });
  }

  // === 绘画手势处理 ===
  // GestureDetector 放在 InteractiveViewer 内部
  // 单指操作用于绘画，双指操作由 InteractiveViewer 处理缩放/平移

  /// 判断点是否在画布范围内
  bool _isInCanvas(Offset point) {
    return point.dx >= -10 &&
        point.dx <= _canvasSize + 10 &&
        point.dy >= -10 &&
        point.dy <= _canvasSize + 10;
  }

  /// 开始绘制
  void _onPanStart(DragStartDetails details) {
    final localPos = details.localPosition;
    if (!_isInCanvas(localPos)) return;

    if (_currentTool == DrawTool.pencil) {
      _pushUndo();
      setState(() {
        _activeStroke = StrokeRecord(
          points: [localPos],
          strokeWidth: _strokeWidth,
          color: _penColor,
        );
      });
    } else if (_currentTool == DrawTool.eraser) {
      _eraseAtPosition(localPos);
    }
  }

  /// 绘制中
  void _onPanUpdate(DragUpdateDetails details) {
    final localPos = details.localPosition;

    if (_currentTool == DrawTool.pencil && _activeStroke != null) {
      setState(() {
        _activeStroke!.points.add(localPos);
      });
    } else if (_currentTool == DrawTool.eraser) {
      _eraseAtPosition(localPos);
      setState(() {
        _eraserPosition = localPos;
      });
    }
  }

  /// 结束绘制
  void _onPanEnd(DragEndDetails details) {
    if (_currentTool == DrawTool.pencil && _activeStroke != null) {
      setState(() {
        _strokes.add(_activeStroke!);
        _activeStroke = null;
      });
    } else if (_currentTool == DrawTool.eraser) {
      setState(() {
        _eraserPosition = null;
      });
    }
  }

  /// 在指定位置执行橡皮擦操作
  void _eraseAtPosition(Offset position) {
    final eraseRadiusSq = _eraserRadius * _eraserRadius;
    bool erased = false;
    // 从后往前遍历，删除最近的笔画
    for (int i = _strokes.length - 1; i >= 0; i--) {
      final stroke = _strokes[i];
      for (final point in stroke.points) {
        final dx = point.dx - position.dx;
        final dy = point.dy - position.dy;
        if (dx * dx + dy * dy <= eraseRadiusSq) {
          if (!erased) {
            _pushUndo();
            erased = true;
          }
          setState(() {
            _strokes.removeAt(i);
          });
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final unicodeHex =
        'U+${widget.glyph.unicode.toRadixString(16).toUpperCase().padLeft(4, '0')}';

    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        // 顶部信息栏
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
            tooltip: '取消',
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 字符预览
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    widget.character,
                    style: TextStyle(
                      fontSize: 20,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 字符和 Unicode 信息
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '编辑「${widget.character}」',
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    '$unicodeHex · ${_strokes.length} 笔画',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            // 撤销按钮
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: _undoStack.isNotEmpty ? _undo : null,
              tooltip: '撤销',
            ),
            // 重做按钮
            IconButton(
              icon: const Icon(Icons.redo),
              onPressed: _redoStack.isNotEmpty ? _redo : null,
              tooltip: '重做',
            ),
            // 适应屏幕
            IconButton(
              icon: const Icon(Icons.fit_screen),
              onPressed: _fitToScreen,
              tooltip: '适应屏幕',
            ),
            // 保存按钮
            FilledButton(
              onPressed: _confirmEdit,
              child: const Text('保存'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            // === 工具参数滑块（根据当前模式切换） ===
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: colorScheme.surfaceContainerLow,
              child: Row(
                children: [
                  // 模式指示图标
                  Icon(
                    _currentTool == DrawTool.eraser
                        ? Icons.cleaning_services
                        : Icons.edit,
                    size: 18,
                    color: _currentTool == DrawTool.eraser
                        ? Colors.red
                        : colorScheme.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Slider(
                      value: _currentTool == DrawTool.eraser
                          ? _eraserRadius
                          : _strokeWidth,
                      min: _currentTool == DrawTool.eraser ? 10.0 : 1.0,
                      max: _currentTool == DrawTool.eraser ? 50.0 : 10.0,
                      divisions: _currentTool == DrawTool.eraser ? 8 : 9,
                      label: _currentTool == DrawTool.eraser
                          ? '${_eraserRadius.round()}px'
                          : '${_strokeWidth.round()}px',
                      onChanged: (v) => setState(() {
                        if (_currentTool == DrawTool.eraser) {
                          _eraserRadius = v;
                        } else {
                          _strokeWidth = v;
                        }
                      }),
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    child: Text(
                      _currentTool == DrawTool.eraser
                          ? '${_eraserRadius.round()}px'
                          : '${_strokeWidth.round()}px',
                      style: TextStyle(
                        fontSize: 12,
                        color: _currentTool == DrawTool.eraser
                            ? Colors.red
                            : colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 预览圆点（显示当前工具大小）
                  Container(
                    width: (_currentTool == DrawTool.eraser
                            ? _eraserRadius
                            : _strokeWidth) *
                            2 +
                        4,
                    height: (_currentTool == DrawTool.eraser
                            ? _eraserRadius
                            : _strokeWidth) *
                            2 +
                        4,
                    decoration: BoxDecoration(
                      color: _currentTool == DrawTool.eraser
                          ? Colors.red.withValues(alpha: 0.3)
                          : _penColor,
                      shape: BoxShape.circle,
                      border: _currentTool == DrawTool.eraser
                          ? Border.all(color: Colors.red, width: 1.5)
                          : null,
                    ),
                  ),
                  // 缩放控制按钮
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.zoom_out, size: 20),
                    onPressed: _zoomOut,
                    tooltip: '缩小',
                    color: colorScheme.onSurfaceVariant,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    icon: const Icon(Icons.zoom_in, size: 20),
                    onPressed: _zoomIn,
                    tooltip: '放大',
                    color: colorScheme.onSurfaceVariant,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),

            // === 画布区域 ===
            Expanded(
              child: Center(
                child: InteractiveViewer(
                  transformationController: _transformController,
                  boundaryMargin: const EdgeInsets.all(100),
                  minScale: 0.2,
                  maxScale: 5.0,
                  // 禁用单指平移，让 GestureDetector 处理绘画
                  panEnabled: false,
                  scaleEnabled: true,
                  child: GestureDetector(
                    onPanStart: _onPanStart,
                    onPanUpdate: _onPanUpdate,
                    onPanEnd: _onPanEnd,
                    child: MouseRegion(
                      cursor: _currentTool == DrawTool.eraser
                          ? SystemMouseCursors.precise
                          : SystemMouseCursors.precise,
                      child: SizedBox(
                        width: _canvasSize,
                        height: _canvasSize,
                        child: Stack(
                          children: [
                            // 白色背景
                            Container(
                              width: _canvasSize,
                              height: _canvasSize,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                  color: colorScheme.outlineVariant,
                                  width: 1,
                                ),
                              ),
                            ),
                            // 米字格辅助线
                            if (_showGrid)
                              CustomPaint(
                                size: const Size(_canvasSize, _canvasSize),
                                painter: _GridPainter(
                                  gridColor: colorScheme.outlineVariant
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                            // 原始手写参考图（半透明）
                            if (_showSourceImage && _sourceImage != null)
                              Positioned.fill(
                                child: Opacity(
                                  opacity: 0.3,
                                  child: Image.memory(
                                    _sourceImage!,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            // 笔画绘制
                            CustomPaint(
                              size: const Size(_canvasSize, _canvasSize),
                              painter: _CanvasPainter(
                                strokes: _strokes,
                                activeStroke: _activeStroke,
                                eraserPosition: _eraserPosition,
                                eraserRadius: _eraserRadius,
                              ),
                            ),
                            // 字符参考（半透明显示）
                            Center(
                              child: Text(
                                widget.character,
                                style: TextStyle(
                                  fontSize: 300,
                                  color: colorScheme.outlineVariant
                                      .withValues(alpha: 0.08),
                                  fontWeight: FontWeight.w100,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // === 底部工具栏 ===
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 铅笔工具
                    _ToolButton(
                      icon: Icons.edit,
                      label: '铅笔',
                      isActive: _currentTool == DrawTool.pencil,
                      onTap: () =>
                          setState(() => _currentTool = DrawTool.pencil),
                      colorScheme: colorScheme,
                    ),
                    // 橡皮擦工具
                    _ToolButton(
                      icon: Icons.cleaning_services,
                      label: '橡皮擦',
                      isActive: _currentTool == DrawTool.eraser,
                      onTap: () =>
                          setState(() => _currentTool = DrawTool.eraser),
                      colorScheme: colorScheme,
                    ),
                    // 画笔粗细
                    _ToolButton(
                      icon: Icons.line_weight,
                      label: '${_strokeWidth.round()}px',
                      isActive: false,
                      onTap: _showBrushWidthDialog,
                      colorScheme: colorScheme,
                    ),
                    // 分隔线
                    Container(
                      width: 1,
                      height: 32,
                      color: colorScheme.outlineVariant,
                    ),
                    // 米字格开关
                    _ToolButton(
                      icon: _showGrid ? Icons.grid_on : Icons.grid_off,
                      label: '米字格',
                      isActive: _showGrid,
                      onTap: () =>
                          setState(() => _showGrid = !_showGrid),
                      colorScheme: colorScheme,
                    ),
                    // 原始手写参考图开关
                    if (_sourceImage != null)
                      _ToolButton(
                        icon: _showSourceImage ? Icons.visibility : Icons.visibility_off,
                        label: '参考图',
                        isActive: _showSourceImage,
                        onTap: () =>
                            setState(() => _showSourceImage = !_showSourceImage),
                        colorScheme: colorScheme,
                      ),
                    // 分隔线
                    Container(
                      width: 1,
                      height: 32,
                      color: colorScheme.outlineVariant,
                    ),
                    // 撤销
                    _ToolButton(
                      icon: Icons.undo,
                      label: '撤销',
                      isActive: false,
                      onTap: _undoStack.isNotEmpty ? _undo : null,
                      colorScheme: colorScheme,
                    ),
                    // 重做
                    _ToolButton(
                      icon: Icons.redo,
                      label: '重做',
                      isActive: false,
                      onTap: _redoStack.isNotEmpty ? _redo : null,
                      colorScheme: colorScheme,
                    ),
                    // 清除
                    _ToolButton(
                      icon: Icons.delete_sweep,
                      label: '清除',
                      isActive: false,
                      onTap: _strokes.isNotEmpty ? _clearAll : null,
                      colorScheme: colorScheme,
                    ),
                    // 分隔线
                    Container(
                      width: 1,
                      height: 32,
                      color: colorScheme.outlineVariant,
                    ),
                    // 字符选择
                    _ToolButton(
                      icon: Icons.text_fields,
                      label: '字符',
                      isActive: false,
                      onTap: () =>
                          _showCharacterPicker(context, colorScheme),
                      colorScheme: colorScheme,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示画笔粗细选择弹窗
  void _showBrushWidthDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('画笔粗细'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  value: _strokeWidth,
                  min: 1.0,
                  max: 10.0,
                  divisions: 9,
                  label: '${_strokeWidth.round()}px',
                  onChanged: (v) {
                    setDialogState(() {});
                    setState(() => _strokeWidth = v);
                  },
                ),
                Text(
                  '${_strokeWidth.round()}px',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 显示常用字符选择器
  void _showCharacterPicker(BuildContext context, ColorScheme colorScheme) {
    final commonChars = StandardCharset.allCharStrings;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollController) {
          return Column(
            children: [
              // 顶部手柄
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '选择字符',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: commonChars.length,
                  itemBuilder: (ctx, index) {
                    final char = commonChars[index];
                    final isSelected = char == _selectedCharacter;
                    return InkWell(
                      onTap: () {
                        _changeCharacter(char);
                        Navigator.pop(ctx);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.primaryContainer
                              : colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
                              ? Border.all(
                                  color: colorScheme.primary, width: 2)
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            char,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 底部工具栏按钮组件
class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  final ColorScheme colorScheme;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color:
              isActive ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: enabled
                  ? (isActive
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface)
                  : colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: enabled
                    ? (isActive
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant)
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
