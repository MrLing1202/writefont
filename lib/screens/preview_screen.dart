import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/storage_service.dart';
import '../widgets/glyph_widget.dart';
import 'character_edit_screen.dart';

class PreviewScreen extends StatefulWidget {
  final FontProject project;

  const PreviewScreen({super.key, required this.project});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  String _previewText = '你好世界 Hello';
  bool _isExporting = false;
  bool _isSaving = false;
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Auto-save debounce
  Timer? _autoSaveTimer;
  bool _isAutoSaving = false;

  // Batch select
  bool _isMultiSelectMode = false;
  final Set<String> _selectedCharacters = {};

  @override
  void initState() {
    super.initState();
    _textController.text = _previewText;
  }

  @override
  void dispose() {
    _textController.dispose();
    _searchController.dispose();
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  /// 导出 TTF 字体（先弹出命名对话框）
  Future<void> _exportFont() async {
    // 弹出字体命名对话框
    final fontName = await _showFontNameDialog();
    if (fontName == null || fontName.isEmpty) return; // 用户取消

    // 更新项目名称
    widget.project.name = fontName;

    setState(() => _isExporting = true);
    try {
      final filePath = await StorageService.exportTtf(widget.project);

      if (mounted) {
        // Show success dialog with install hint
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            icon: Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
              size: 48,
            ),
            title: const Text('导出成功'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('字体文件已保存到：'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    filePath,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '共导出 ${widget.project.glyphs.length} 个字符',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                // 安装提示
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '安装字体：将 TTF 文件发送到电脑，双击安装即可在设计软件中使用。Android 可通过「设置→显示→字体」导入。',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  StorageService.shareTtf(filePath);
                },
                icon: const Icon(Icons.share),
                label: const Text('分享'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString();
        String userMessage;
        if (errorMsg.contains('No such file') || errorMsg.contains('Permission')) {
          userMessage = '导出失败：存储权限不足，请在系统设置中允许存储权限后重试';
        } else if (errorMsg.contains('disk') || errorMsg.contains('space') || errorMsg.contains('full')) {
          userMessage = '导出失败：存储空间不足，请清理手机空间后重试';
        } else {
          userMessage = '导出失败：请检查字符数据是否完整，或尝试重新生成字体';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userMessage),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// 显示字体命名对话框，返回用户输入的字体名称（取消返回 null）
  Future<String?> _showFontNameDialog() async {
    final controller = TextEditingController(text: widget.project.name);
    final formKey = GlobalKey<FormState>();

    // 取前 5 个有轮廓的字符用于预览
    final previewGlyphs = widget.project.glyphs.entries
        .where((e) => e.value.contours.isNotEmpty)
        .take(5)
        .toList();

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              icon: Icon(Icons.font_download, color: colorScheme.primary, size: 36),
              title: const Text('为你的字体命名'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '这个名字将作为字体文件名和项目标题',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: '字体名称',
                        hintText: '例如：我的手写体',
                        prefixIcon: const Icon(Icons.edit),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入字体名称';
                        }
                        // 检查非法文件名字符
                        if (RegExp(r'[<>:"/\\|?*]').hasMatch(value)) {
                          return '名称不能包含特殊字符';
                        }
                        return null;
                      },
                      maxLength: 30,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setDialogState(() {}),
                      onFieldSubmitted: (_) {
                        if (formKey.currentState!.validate()) {
                          Navigator.pop(context, controller.text.trim());
                        }
                      },
                    ),
                    // 字体预览区域
                    if (previewGlyphs.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Card(
                        elevation: 0,
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.preview, size: 16, color: colorScheme.primary),
                                  const SizedBox(width: 6),
                                  Text(
                                    '预览效果',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // 字体名称预览
                              Text(
                                controller.text.isEmpty ? '字体名称' : controller.text,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // 字形预览
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: previewGlyphs.map((entry) {
                                  return Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: colorScheme.outlineVariant,
                                      ),
                                      color: colorScheme.surface,
                                    ),
                                    child: Center(
                                      child: GlyphWidget(
                                        contours: entry.value.contours,
                                        size: 32,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.pop(context, controller.text.trim());
                    }
                  },
                  child: const Text('导出'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return result;
  }

  /// 自动保存（带 1 秒 debounce）
  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 1), () async {
      if (!mounted) return;
      setState(() => _isAutoSaving = true);
      try {
        await StorageService.saveProject(widget.project);
      } catch (_) {
        // Auto-save failure is silent
      } finally {
        if (mounted) setState(() => _isAutoSaving = false);
      }
    });
  }

  /// 保存项目到本地
  Future<void> _saveProject() async {
    setState(() => _isSaving = true);
    try {
      await StorageService.saveProject(widget.project);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('项目「${widget.project.name}」已保存'),
            action: SnackBarAction(
              label: '知道了',
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 导出项目备份（JSON 格式，含源图片 base64）
  Future<void> _exportProjectBackup() async {
    try {
      final filePath = await StorageService.exportProject(widget.project);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('备份已导出: ${widget.project.name}_backup.json'),
            action: SnackBarAction(
              label: '分享',
              onPressed: () {
                StorageService.shareTtf(filePath);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份导出失败: $e')),
        );
      }
    }
  }

  /// 打开字符编辑对话框
  void _editCharacter(String character, GlyphData glyph) {
    if (_isMultiSelectMode) {
      _toggleSelection(character);
      return;
    }
    CharacterEditDialog.show(
      context,
      character: character,
      glyph: glyph,
      projectId: widget.project.id,
      onCharacterChanged: () {
        // 如果字符标签改变了，需要更新 glyphs Map
        if (glyph.character != character) {
          widget.project.glyphs.remove(character);
          widget.project.glyphs[glyph.character] = glyph;
        }
        setState(() {});
        _scheduleAutoSave();
      },
      onCharacterDeleted: () {
        widget.project.glyphs.remove(character);
        setState(() {});
        _scheduleAutoSave();
      },
    );
  }

  /// 切换多选状态
  void _toggleSelection(String character) {
    setState(() {
      if (_selectedCharacters.contains(character)) {
        _selectedCharacters.remove(character);
        if (_selectedCharacters.isEmpty) {
          _isMultiSelectMode = false;
        }
      } else {
        _selectedCharacters.add(character);
      }
    });
  }

  /// 进入多选模式
  void _enterMultiSelectMode(String character) {
    setState(() {
      _isMultiSelectMode = true;
      _selectedCharacters.add(character);
    });
  }

  /// 退出多选模式
  void _exitMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedCharacters.clear();
    });
  }

  /// 批量删除选中的字符
  Future<void> _deleteSelectedCharacters() async {
    final count = _selectedCharacters.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 $count 个字符吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        for (final char in _selectedCharacters) {
          widget.project.glyphs.remove(char);
        }
        _selectedCharacters.clear();
        _isMultiSelectMode = false;
      });
      _scheduleAutoSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final glyphs = widget.project.glyphs;

    return Scaffold(
      appBar: AppBar(
        title: _isMultiSelectMode
            ? Text('已选 ${_selectedCharacters.length} 个')
            : const Text('字体预览'),
        leading: _isMultiSelectMode
            ? IconButton(
                onPressed: _exitMultiSelectMode,
                icon: const Icon(Icons.close),
              )
            : null,
        actions: _isMultiSelectMode
            ? [
                IconButton(
                  onPressed: _deleteSelectedCharacters,
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: '删除选中',
                ),
              ]
            : [
                if (_isAutoSaving)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                IconButton(
                  onPressed: () => _showGlyphList(colorScheme),
                  icon: const Icon(Icons.list),
                  tooltip: '查看字符列表',
                ),
              ],
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Row(
              children: [
                Icon(Icons.font_download, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '${widget.project.name} · ${glyphs.length} 个字符',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                // 字符可点击提示
                Icon(
                  Icons.touch_app,
                  size: 16,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  '点击字符可编辑',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),

          // Preview input
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _textController,
              decoration: InputDecoration(
                labelText: '预览文字',
                hintText: '输入要预览的文字',
                prefixIcon: const Icon(Icons.text_fields),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _textController.clear();
                    setState(() => _previewText = '');
                  },
                ),
              ),
              onChanged: (v) => setState(() => _previewText = v),
              maxLines: 2,
            ),
          ),

          // Preview area
          Expanded(
            child: _previewText.isEmpty
                ? Center(
                    child: Text(
                      '输入文字查看预览效果',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        fontSize: 16,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Large preview
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: colorScheme.outlineVariant),
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '大字预览',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _buildGlyphPreviewText(_previewText, 48),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Medium preview
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: colorScheme.outlineVariant),
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '中字预览',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildGlyphPreviewText(_previewText, 28),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Small preview
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: colorScheme.outlineVariant),
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '小字预览',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _buildGlyphPreviewText(_previewText, 16),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Character grid preview
                        Text(
                          '已收录字符',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '点击字符可编辑 · 长按批量选择',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Search box
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: '搜索字符或 Unicode 编码...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onChanged: (v) => setState(() => _searchQuery = v),
                        ),
                        const SizedBox(height: 8),
                        _buildCharacterGrid(glyphs, colorScheme),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 保存项目 + 导出备份按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving ? null : _saveProject,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(_isSaving ? '保存中...' : '保存项目'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _exportProjectBackup,
                      icon: const Icon(Icons.backup),
                      label: const Text('导出备份'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 底部操作按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.edit),
                      label: const Text('返回编辑'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _isExporting ? null : _exportFont,
                      icon: _isExporting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.file_download),
                      label: Text(_isExporting ? '导出中...' : '导出 TTF'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlyphPreviewText(String text, double fontSize) {
    final colorScheme = Theme.of(context).colorScheme;
    final List<InlineSpan> spans = [];

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      final glyph = widget.project.glyphs[char];

      if (glyph != null && glyph.contours.isNotEmpty) {
        // We have this glyph - render it using a custom painter approach
        spans.add(WidgetSpan(
          child: GlyphWidget(
            contours: glyph.contours,
            size: fontSize,
            color: colorScheme.onSurface,
          ),
          alignment: PlaceholderAlignment.middle,
        ));
      } else {
        // Use default font
        spans.add(TextSpan(
          text: char,
          style: TextStyle(
            fontSize: fontSize,
            color: colorScheme.onSurface,
          ),
        ));
      }
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  Widget _buildCharacterGrid(Map<String, GlyphData> glyphs, ColorScheme colorScheme) {
    // Filter glyphs based on search query
    final filteredEntries = glyphs.entries.where((entry) {
      if (_searchQuery.isEmpty) return true;
      final query = _searchQuery.toLowerCase();
      final character = entry.key;
      final unicodeHex = entry.value.unicode.toRadixString(16).toUpperCase().padLeft(4, '0');
      return character.toLowerCase().contains(query) ||
          unicodeHex.toLowerCase().contains(query) ||
          'U+$unicodeHex'.toLowerCase().contains(query);
    }).toList();

    if (filteredEntries.isEmpty && _searchQuery.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        alignment: Alignment.center,
        child: Text(
          '未找到匹配的字符',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            fontSize: 14,
          ),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: filteredEntries.map((entry) {
        final glyph = entry.value;
        final character = entry.key;
        final unicodeHex = 'U+${glyph.unicode.toRadixString(16).toUpperCase().padLeft(4, '0')}';
        final isSelected = _selectedCharacters.contains(character);
        return GestureDetector(
          onTap: () => _editCharacter(character, glyph),
          onLongPress: () => _enterMultiSelectMode(character),
          child: Tooltip(
            message: '$unicodeHex · 点击编辑',
            child: Container(
              width: 48,
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
                  width: isSelected ? 2.5 : 1,
                ),
                color: colorScheme.surface,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        glyph.contours.isNotEmpty
                            ? GlyphWidget(
                            contours: glyph.contours,
                            size: 32,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                          )
                            : Center(
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                fontSize: 20,
                                color: isSelected
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                            ),
                          ),
                        if (isSelected)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(1),
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.check,
                                size: 12,
                                color: colorScheme.onPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    unicodeHex.substring(2), // 显示 4 位十六进制
                    style: TextStyle(
                      fontSize: 8,
                      color: colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showGlyphList(ColorScheme colorScheme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) {
          final glyphs = widget.project.glyphs.entries.toList();
          return Column(
            children: [
              // Handle
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
                  '字符列表 (${glyphs.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: glyphs.length,
                  itemBuilder: (context, index) {
                    final entry = glyphs[index];
                    return ListTile(
                      onTap: () {
                        Navigator.pop(context);
                        _editCharacter(entry.key, entry.value);
                      },
                      leading: SizedBox(
                        width: 40,
                        height: 40,
                        child: entry.value.contours.isNotEmpty
                            ? GlyphWidget(
                                contours: entry.value.contours,
                                size: 32,
                                color: colorScheme.onSurface,
                              )
                            : Center(
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                      ),
                      title: Text('U+${entry.value.unicode.toRadixString(16).toUpperCase().padLeft(4, '0')}'),
                      subtitle: Text('${entry.value.contours.length} 个轮廓'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(fontSize: 24),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.edit,
                            size: 16,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ],
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


