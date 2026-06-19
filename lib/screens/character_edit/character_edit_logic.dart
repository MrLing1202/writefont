import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../data/standard_charset.dart';
import '../../models/project.dart';
import '../../services/storage_service.dart';
import 'drawing_models.dart';

import '../character_edit_screen.dart';
/// CharacterEditDialog 的业务逻辑 mixin
///
/// 包含绘画状态、手势处理、撤销重做、自动保存、缩放平移等方法。
mixin CharacterEditLogic on State<CharacterEditDialog> {
  TextEditingController charController = TextEditingController();
  String selectedCharacter = '';
  Uint8List? sourceImage;
  bool isLoadingImage = false;

  // === 自动保存 ===
  static const Duration autoSaveInterval = Duration(seconds: 30);
  Timer? autoSaveTimer;
  bool isDirty = false;

  // === 绘画相关状态 ===
  /// 当前工具模式
  DrawTool currentTool = DrawTool.pencil;

  /// 已完成的笔画列表
  final List<StrokeRecord> strokes = [];

  /// 当前正在绘制的笔画
  StrokeRecord? activeStroke;

  /// 橡皮擦当前位置（用于显示光标）
  Offset? eraserPosition;

  /// 笔画宽度（1-10像素）
  double strokeWidth = 3.0;

  /// 画笔颜色
  final Color penColor = Colors.black;

  /// 米字格辅助线开关
  bool showGrid = true;

  /// 原始手写参考图显示开关
  bool showSourceImage = false;

  /// 橡皮擦半径（10-50px，独立可调）
  double eraserRadius = 20.0;

  // === 缩放/平移 ===
  final TransformationController transformController =
      TransformationController();

  // === 撤销/重做 ===
  static const int maxHistorySize = 30;
  final List<List<StrokeRecord>> undoStack = [];
  final List<List<StrokeRecord>> redoStack = [];

  // === 画布尺寸 ===
  static const double canvasSize = 500.0;

  void initLogic() {
    selectedCharacter = widget.character;
    charController.text = widget.character;
    loadSourceImage();
    loadContoursToStrokes();
    // 启动30秒自动保存定时器
    autoSaveTimer = Timer.periodic(autoSaveInterval, (_) => autoSave());
  }

  void disposeLogic() {
    autoSaveTimer?.cancel();
    // 退出前执行最后一次保存
    autoSave();
    charController.dispose();
    transformController.dispose();
  }

  /// 自动保存：将当前笔画同步到 GlyphData 轮廓
  void autoSave() {
    if (strokes.isEmpty || !isDirty) return;
    saveStrokesToContours();
    isDirty = false;
    debugPrint('自动保存: 已保存 ${strokes.length} 个笔画到轮廓');
  }

  /// 从 GlyphData 轮廓加载已有笔画
  void loadContoursToStrokes() {
    for (final contour in widget.glyph.contours) {
      if (contour.points.isEmpty) continue;
      final points = contour.points
          .map((p) => Offset(p.x.toDouble(), p.y.toDouble()))
          .toList();
      strokes.add(StrokeRecord(
        points: points,
        strokeWidth: strokeWidth,
        color: penColor,
      ));
    }
  }

  /// 将当前笔画保存到 GlyphData 轮廓
  void saveStrokesToContours() {
    widget.glyph.contours.clear();
    for (final stroke in strokes) {
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
  Future<void> loadSourceImage() async {
    if (widget.projectId == null) return;
    setState(() => isLoadingImage = true);
    try {
      final image = await StorageService.loadCharacterImage(
        widget.projectId!,
        widget.character,
      );
      if (mounted) {
        setState(() {
          sourceImage = image;
          isLoadingImage = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoadingImage = false);
    }
  }

  /// 修改字符标签
  void changeCharacter(String newChar) {
    if (newChar.isEmpty || newChar == widget.character) return;
    setState(() {
      selectedCharacter = newChar;
      charController.text = newChar;
    });
  }

  /// 确认修改并退出
  void confirmEdit() {
    // 保存笔画到轮廓
    saveStrokesToContours();
    if (selectedCharacter != widget.character &&
        selectedCharacter.isNotEmpty) {
      widget.glyph.character = selectedCharacter;
      widget.glyph.unicode = selectedCharacter.codeUnitAt(0);
    }
    widget.onCharacterChanged();
    Navigator.pop(context);
  }

  /// 按关闭按钮时检查未保存修改
  Future<void> onClosePressed() async {
    if (!isDirty) {
      Navigator.pop(context);
      return;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.save_outlined,
          color: Theme.of(ctx).colorScheme.primary,
          size: 36,
        ),
        title: const Text('未保存的修改'),
        content: const Text('有未保存的修改，是否保存？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('不保存'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    switch (result) {
      case 'save':
        confirmEdit();
        break;
      case 'discard':
        Navigator.pop(context);
        break;
      // 'cancel' or dismissed: do nothing
    }
  }

  /// 删除字符
  void deleteCharacter() {
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
  void pushUndo() {
    undoStack.add(List<StrokeRecord>.from(strokes));
    if (undoStack.length > maxHistorySize) {
      undoStack.removeAt(0);
    }
    redoStack.clear();
  }

  /// 撤销
  void undo() {
    if (undoStack.isEmpty) return;
    redoStack.add(List<StrokeRecord>.from(strokes));
    final previous = undoStack.removeLast();
    setState(() {
      strokes.clear();
      strokes.addAll(previous);
    });
  }

  /// 重做
  void redo() {
    if (redoStack.isEmpty) return;
    undoStack.add(List<StrokeRecord>.from(strokes));
    final next = redoStack.removeLast();
    setState(() {
      strokes.clear();
      strokes.addAll(next);
      isDirty = true;
    });
  }

  /// 清除所有笔画
  void clearAll() {
    if (strokes.isEmpty) return;
    pushUndo();
    setState(() {
      strokes.clear();
      eraserPosition = null;
      isDirty = true;
    });
  }

  /// 适应屏幕 - 重置视图
  void fitToScreen() {
    setState(() {
      transformController.value = Matrix4.identity();
    });
  }

  /// 放大
  void zoomIn() {
    final matrix = transformController.value.clone();
    matrix.scale(1.2);
    setState(() {
      transformController.value = matrix;
    });
  }

  /// 缩小
  void zoomOut() {
    final matrix = transformController.value.clone();
    matrix.scale(1 / 1.2);
    setState(() {
      transformController.value = matrix;
    });
  }

  // === 绘画手势处理 ===

  /// 判断点是否在画布范围内
  bool isInCanvas(Offset point) {
    return point.dx >= -10 &&
        point.dx <= canvasSize + 10 &&
        point.dy >= -10 &&
        point.dy <= canvasSize + 10;
  }

  /// 开始绘制
  void onPanStart(DragStartDetails details) {
    final localPos = details.localPosition;
    if (!isInCanvas(localPos)) return;

    if (currentTool == DrawTool.pencil) {
      pushUndo();
      setState(() {
        activeStroke = StrokeRecord(
          points: [localPos],
          strokeWidth: strokeWidth,
          color: penColor,
        );
      });
    } else if (currentTool == DrawTool.eraser) {
      eraseAtPosition(localPos);
    }
  }

  /// 绘制中
  void onPanUpdate(DragUpdateDetails details) {
    final localPos = details.localPosition;

    if (currentTool == DrawTool.pencil && activeStroke != null) {
      setState(() {
        activeStroke!.points.add(localPos);
      });
    } else if (currentTool == DrawTool.eraser) {
      eraseAtPosition(localPos);
      setState(() {
        eraserPosition = localPos;
      });
    }
  }

  /// 结束绘制
  void onPanEnd(DragEndDetails details) {
    if (currentTool == DrawTool.pencil && activeStroke != null) {
      setState(() {
        strokes.add(activeStroke!);
        activeStroke = null;
        isDirty = true;
      });
    } else if (currentTool == DrawTool.eraser) {
      setState(() {
        eraserPosition = null;
      });
    }
  }

  /// 在指定位置执行橡皮擦操作
  void eraseAtPosition(Offset position) {
    final eraseRadiusSq = eraserRadius * eraserRadius;
    bool erased = false;
    // 从后往前遍历，删除最近的笔画
    for (int i = strokes.length - 1; i >= 0; i--) {
      final stroke = strokes[i];
      for (final point in stroke.points) {
        final dx = point.dx - position.dx;
        final dy = point.dy - position.dy;
        if (dx * dx + dy * dy <= eraseRadiusSq) {
          if (!erased) {
            pushUndo();
            erased = true;
          }
          setState(() {
            strokes.removeAt(i);
            isDirty = true;
          });
          break;
        }
      }
    }
  }
}
