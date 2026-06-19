import 'package:flutter/material.dart';
import '../data/standard_charset.dart';
import '../models/project.dart';
import '../theme/app_theme.dart';
import 'character_edit/drawing_models.dart';
import 'character_edit/canvas_painters.dart';
import 'character_edit/tool_button.dart';
import 'character_edit/character_edit_logic.dart';

// Re-export split modules so external imports remain valid
export 'character_edit/drawing_models.dart';

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

class _CharacterEditDialogState extends State<CharacterEditDialog>
    with CharacterEditLogic {
  @override
  void initState() {
    super.initState();
    initLogic();
  }

  @override
  void dispose() {
    disposeLogic();
    super.dispose();
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
        appBar: WFAppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: onClosePressed,
            tooltip: '取消',
          ),
          titleWidget: Row(
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
                    '$unicodeHex · ${strokes.length} 笔画',
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
              onPressed: undoStack.isNotEmpty ? undo : null,
              tooltip: '撤销',
            ),
            // 重做按钮
            IconButton(
              icon: const Icon(Icons.redo),
              onPressed: redoStack.isNotEmpty ? redo : null,
              tooltip: '重做',
            ),
            // 适应屏幕
            IconButton(
              icon: const Icon(Icons.fit_screen),
              onPressed: fitToScreen,
              tooltip: '适应屏幕',
            ),
            // 保存按钮
            FilledButton(
              onPressed: confirmEdit,
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
                    currentTool == DrawTool.eraser
                        ? Icons.cleaning_services
                        : Icons.edit,
                    size: 18,
                    color: currentTool == DrawTool.eraser
                        ? Colors.red
                        : colorScheme.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Slider(
                      value: currentTool == DrawTool.eraser
                          ? eraserRadius
                          : strokeWidth,
                      min: currentTool == DrawTool.eraser ? 10.0 : 1.0,
                      max: currentTool == DrawTool.eraser ? 50.0 : 10.0,
                      divisions: currentTool == DrawTool.eraser ? 8 : 9,
                      label: currentTool == DrawTool.eraser
                          ? '${eraserRadius.round()}px'
                          : '${strokeWidth.round()}px',
                      onChanged: (v) => setState(() {
                        if (currentTool == DrawTool.eraser) {
                          eraserRadius = v;
                        } else {
                          strokeWidth = v;
                        }
                      }),
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    child: Text(
                      currentTool == DrawTool.eraser
                          ? '${eraserRadius.round()}px'
                          : '${strokeWidth.round()}px',
                      style: TextStyle(
                        fontSize: 12,
                        color: currentTool == DrawTool.eraser
                            ? Colors.red
                            : colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 预览圆点（显示当前工具大小）
                  Container(
                    width: (currentTool == DrawTool.eraser
                            ? eraserRadius
                            : strokeWidth) *
                            2 +
                        4,
                    height: (currentTool == DrawTool.eraser
                            ? eraserRadius
                            : strokeWidth) *
                            2 +
                        4,
                    decoration: BoxDecoration(
                      color: currentTool == DrawTool.eraser
                          ? Colors.red.withValues(alpha: 0.3)
                          : penColor,
                      shape: BoxShape.circle,
                      border: currentTool == DrawTool.eraser
                          ? Border.all(color: Colors.red, width: 1.5)
                          : null,
                    ),
                  ),
                  // 缩放控制按钮
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.zoom_out, size: 20),
                    onPressed: zoomOut,
                    tooltip: '缩小',
                    color: colorScheme.onSurfaceVariant,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                  ),
                  IconButton(
                    icon: const Icon(Icons.zoom_in, size: 20),
                    onPressed: zoomIn,
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
                  transformationController: transformController,
                  boundaryMargin: const EdgeInsets.all(100),
                  minScale: 0.2,
                  maxScale: 5.0,
                  // 禁用单指平移，让 GestureDetector 处理绘画
                  panEnabled: false,
                  scaleEnabled: true,
                  child: GestureDetector(
                    onPanStart: onPanStart,
                    onPanUpdate: onPanUpdate,
                    onPanEnd: onPanEnd,
                    child: MouseRegion(
                      cursor: currentTool == DrawTool.eraser
                          ? SystemMouseCursors.precise
                          : SystemMouseCursors.precise,
                      child: SizedBox(
                        width: CharacterEditLogic.canvasSize,
                        height: CharacterEditLogic.canvasSize,
                        child: Stack(
                          children: [
                            // 白色背景
                            Container(
                              width: CharacterEditLogic.canvasSize,
                              height: CharacterEditLogic.canvasSize,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                  color: colorScheme.outlineVariant,
                                  width: 1,
                                ),
                              ),
                            ),
                            // 米字格辅助线
                            if (showGrid)
                              CustomPaint(
                                size: const Size(CharacterEditLogic.canvasSize, CharacterEditLogic.canvasSize),
                                painter: GridPainter(
                                  gridColor: colorScheme.outlineVariant
                                      .withValues(alpha: 0.4),
                                ),
                              ),
                            // 原始手写参考图（半透明）
                            if (showSourceImage && sourceImage != null)
                              Positioned.fill(
                                child: Opacity(
                                  opacity: 0.3,
                                  child: Image.memory(
                                    sourceImage!,
                                    fit: BoxFit.contain,
                                    cacheWidth: 800,
                                    cacheHeight: 800,
                                  ),
                                ),
                              ),
                            // 笔画绘制
                            CustomPaint(
                              size: const Size(CharacterEditLogic.canvasSize, CharacterEditLogic.canvasSize),
                              painter: CanvasPainter(
                                strokes: strokes,
                                activeStroke: activeStroke,
                                eraserPosition: eraserPosition,
                                eraserRadius: eraserRadius,
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
                    ToolButton(
                      icon: Icons.edit,
                      label: '铅笔',
                      isActive: currentTool == DrawTool.pencil,
                      onTap: () =>
                          setState(() => currentTool = DrawTool.pencil),
                      colorScheme: colorScheme,
                    ),
                    // 橡皮擦工具
                    ToolButton(
                      icon: Icons.cleaning_services,
                      label: '橡皮擦',
                      isActive: currentTool == DrawTool.eraser,
                      onTap: () =>
                          setState(() => currentTool = DrawTool.eraser),
                      colorScheme: colorScheme,
                    ),
                    // 画笔粗细
                    ToolButton(
                      icon: Icons.line_weight,
                      label: '${strokeWidth.round()}px',
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
                    ToolButton(
                      icon: showGrid ? Icons.grid_on : Icons.grid_off,
                      label: '米字格',
                      isActive: showGrid,
                      onTap: () =>
                          setState(() => showGrid = !showGrid),
                      colorScheme: colorScheme,
                    ),
                    // 原始手写参考图开关
                    if (sourceImage != null)
                      ToolButton(
                        icon: showSourceImage ? Icons.visibility : Icons.visibility_off,
                        label: '参考图',
                        isActive: showSourceImage,
                        onTap: () =>
                            setState(() => showSourceImage = !showSourceImage),
                        colorScheme: colorScheme,
                      ),
                    // 分隔线
                    Container(
                      width: 1,
                      height: 32,
                      color: colorScheme.outlineVariant,
                    ),
                    // 撤销
                    ToolButton(
                      icon: Icons.undo,
                      label: '撤销',
                      isActive: false,
                      onTap: undoStack.isNotEmpty ? undo : null,
                      colorScheme: colorScheme,
                    ),
                    // 重做
                    ToolButton(
                      icon: Icons.redo,
                      label: '重做',
                      isActive: false,
                      onTap: redoStack.isNotEmpty ? redo : null,
                      colorScheme: colorScheme,
                    ),
                    // 清除
                    ToolButton(
                      icon: Icons.delete_sweep,
                      label: '清除',
                      isActive: false,
                      onTap: strokes.isNotEmpty ? clearAll : null,
                      colorScheme: colorScheme,
                    ),
                    // 分隔线
                    Container(
                      width: 1,
                      height: 32,
                      color: colorScheme.outlineVariant,
                    ),
                    // 字符选择
                    ToolButton(
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
                  value: strokeWidth,
                  min: 1.0,
                  max: 10.0,
                  divisions: 9,
                  label: '${strokeWidth.round()}px',
                  onChanged: (v) {
                    setDialogState(() {});
                    setState(() => strokeWidth = v);
                  },
                ),
                Text(
                  '${strokeWidth.round()}px',
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
                    final isSelected = char == selectedCharacter;
                    return InkWell(
                      onTap: () {
                        changeCharacter(char);
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
