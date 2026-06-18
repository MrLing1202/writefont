import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../data/standard_charset.dart';
import '../models/project.dart';
import '../services/storage_service.dart';

// 使用 StandardCharset.allCharStrings 获取标准字符列表

/// 字符编辑对话框：允许用户修改字符标签、删除字符、查看原始图片
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

  @override
  void initState() {
    super.initState();
    _selectedCharacter = widget.character;
    _charController = TextEditingController(text: widget.character);
    _loadSourceImage();
  }

  @override
  void dispose() {
    _charController.dispose();
    super.dispose();
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

  /// 确认修改
  void _confirmEdit() {
    if (_selectedCharacter != widget.character && _selectedCharacter.isNotEmpty) {
      // 修改字符标签
      widget.glyph.character = _selectedCharacter;
      widget.glyph.unicode = _selectedCharacter.codeUnitAt(0);
      widget.onCharacterChanged();
    }
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final unicodeHex =
        'U+${widget.glyph.unicode.toRadixString(16).toUpperCase().padLeft(4, '0')}';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          // 字符预览
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                widget.character,
                style: TextStyle(
                  fontSize: 32,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '编辑字符',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  '$unicodeHex · ${widget.glyph.contours.length} 个轮廓',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 字符标签修改
              Text(
                '修改字符标签',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  // 手动输入
                  Expanded(
                    child: TextField(
                      controller: _charController,
                      maxLength: 1,
                      decoration: InputDecoration(
                        labelText: '输入新字符',
                        hintText: '输入一个字符',
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (v) {
                        if (v.isNotEmpty) {
                          setState(() => _selectedCharacter = v);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 从常用字符选择
                  FilledButton.tonal(
                    onPressed: () => _showCharacterPicker(context, colorScheme),
                    child: const Text('选择'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 原始图片预览
              Text(
                '原始图片',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 160,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: _isLoadingImage
                    ? const Center(child: CircularProgressIndicator())
                    : _sourceImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              _sourceImage!,
                              fit: BoxFit.contain,
                            ),
                          )
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.image_not_supported_outlined,
                                  size: 40,
                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '暂无原始图片',
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
              ),
              const SizedBox(height: 16),

              // 字形信息
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildInfoRow('Unicode', unicodeHex, colorScheme),
                    _buildInfoRow('字符', widget.character, colorScheme),
                    _buildInfoRow('轮廓数', '${widget.glyph.contours.length}', colorScheme),
                    _buildInfoRow('字宽', '${widget.glyph.advanceWidth}', colorScheme),
                    _buildInfoRow(
                      '边界框',
                      '(${widget.glyph.xMin}, ${widget.glyph.yMin}) - (${widget.glyph.xMax}, ${widget.glyph.yMax})',
                      colorScheme,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        // 删除按钮
        TextButton.icon(
          onPressed: _deleteCharacter,
          icon: Icon(Icons.delete_outline, color: colorScheme.error),
          label: Text('删除', style: TextStyle(color: colorScheme.error)),
        ),
        const Spacer(),
        // 取消按钮
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        // 确认按钮
        FilledButton(
          onPressed: _confirmEdit,
          child: const Text('确认'),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  /// 显示常用字符选择器
  void _showCharacterPicker(BuildContext context, ColorScheme colorScheme) {
    // 使用 StandardCharset 中的字符
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
                              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
                              ? Border.all(color: colorScheme.primary, width: 2)
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            char,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight:
                                  isSelected ? FontWeight.bold : FontWeight.normal,
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
