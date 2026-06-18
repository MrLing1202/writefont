import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glyph_widget.dart';
import 'character_edit_screen.dart';
import 'font_metadata_screen.dart';

/// 预览导出页面
/// 使用 WFCard / WFAppBar / WFPrimaryButton / WFDialog 统一设计风格
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

  // 字体元数据（从 FontMetadataScreen 编辑后回传）
  FontMetadata? _fontMetadata;

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

  // ═══════════════════════════════════════════════════════════
  // 导出逻辑
  // ═══════════════════════════════════════════════════════════

  /// 导出 TTF 字体 — 先弹出确认对话框，再弹命名框
  Future<void> _exportFont() async {
    // 如果已编辑元数据，直接使用；否则弹出旧版确认框
    if (_fontMetadata != null) {
      setState(() => _isExporting = true);
      try {
        final meta = _fontMetadata!;
        widget.project.name = meta.familyName;
        final filePath = await StorageService.exportTtf(
          widget.project,
          familyName: meta.familyName,
          subfamilyName: meta.subfamilyName,
          version: meta.version,
          copyright: meta.copyright,
          description: meta.description,
        );
        if (mounted) _showExportSuccessDialog(filePath);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('导出失败：请检查字符数据是否完整')),
          );
        }
      } finally {
        if (mounted) setState(() => _isExporting = false);
      }
      return;
    }

    // 未编辑元数据 — 走旧流程
    final confirmed = await _showExportConfirmDialog();
    if (confirmed != true) return;

    final fontName = await _showFontNameDialog();
    if (fontName == null || fontName.isEmpty) return;

    widget.project.name = fontName;

    setState(() => _isExporting = true);
    try {
      final filePath = await StorageService.exportTtf(widget.project);

      if (mounted) {
        _showExportSuccessDialog(filePath);
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

  /// 跳转到元数据编辑页面
  Future<void> _editMetadata() async {
    final result = await Navigator.push<FontMetadata>(
      context,
      WFAnimations.slideRoute(FontMetadataScreen(project: widget.project)),
    );
    if (result != null) {
      setState(() => _fontMetadata = result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('元数据已更新，可直接导出字体')),
        );
      }
    }
  }

  /// 显示导出确认对话框（WFDialog 样式）
  Future<bool?> _showExportConfirmDialog() async {
    final glyphs = widget.project.glyphs;
    final editedCount = glyphs.values.where((g) => g.contours.isNotEmpty).length;

    return WFDialog.show<bool>(
      context,
      title: '导出字体',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 字体信息摘要
          _buildInfoRow(Icons.font_download, '字体名称', widget.project.name),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.text_fields, '已生成字符', '$editedCount / ${glyphs.length}'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.calendar_today, '创建日期',
              '${widget.project.createdAt.year}-${widget.project.createdAt.month.toString().padLeft(2, '0')}-${widget.project.createdAt.day.toString().padLeft(2, '0')}'),
          const SizedBox(height: 16),
          // 安装提示
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: WFColors.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: WFColors.info.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: WFColors.info),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '导出为 TTF 字体文件，可在电脑或手机上安装使用。',
                    style: TextStyle(fontSize: 12, color: WFColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        WFPrimaryButton(
          text: '继续导出',
          icon: Icons.file_download,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
  }

  /// 信息行 — 用于对话框内展示
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: WFColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          '$label：',
          style: const TextStyle(fontSize: 13, color: WFColors.textSecondary),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: WFColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  /// 导出成功对话框 — 含分享按钮
  void _showExportSuccessDialog(String filePath) {
    WFDialog.show(
      context,
      title: '导出成功',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 文件路径
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: WFColors.bgPrimary,
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
            style: const TextStyle(color: WFColors.textSecondary),
          ),
          const SizedBox(height: 12),
          // 安装提示
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: WFColors.success.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: WFColors.success.withValues(alpha: 0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline, size: 18, color: WFColors.success),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '安装字体：将 TTF 文件发送到电脑，双击安装即可在设计软件中使用。Android 可通过「设置→显示→字体」导入。',
                    style: TextStyle(fontSize: 12, color: WFColors.textSecondary),
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
        WFPrimaryButton(
          text: '分享',
          icon: Icons.share,
          onPressed: () {
            Navigator.pop(context);
            StorageService.shareTtf(filePath);
          },
        ),
      ],
    );
  }

  /// 显示字体命名对话框
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
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              icon: const Icon(Icons.font_download, color: WFColors.primary, size: 36),
              title: const Text('为你的字体命名'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '这个名字将作为字体文件名和项目标题',
                      style: TextStyle(fontSize: 13, color: WFColors.textSecondary),
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
                      WFCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.preview, size: 16, color: WFColors.primary),
                                SizedBox(width: 6),
                                Text(
                                  '预览效果',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: WFColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              controller.text.isEmpty ? '字体名称' : controller.text,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: WFColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: previewGlyphs.map((entry) {
                                return Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: WFColors.textLight),
                                    color: WFColors.bgPrimary,
                                  ),
                                  child: Center(
                                    child: GlyphWidget(
                                      contours: entry.value.contours,
                                      size: 32,
                                      color: WFColors.textPrimary,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
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

  // ═══════════════════════════════════════════════════════════
  // 保存 & 备份
  // ═══════════════════════════════════════════════════════════

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
            action: SnackBarAction(label: '知道了', onPressed: () {}),
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

  /// 导出项目备份（JSON 格式）
  Future<void> _exportProjectBackup() async {
    try {
      final filePath = await StorageService.exportProject(widget.project);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('备份已导出: ${widget.project.name}_backup.json'),
            action: SnackBarAction(
              label: '分享',
              onPressed: () => StorageService.shareTtf(filePath),
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

  // ═══════════════════════════════════════════════════════════
  // 字符编辑 & 多选
  // ═══════════════════════════════════════════════════════════

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

  void _toggleSelection(String character) {
    setState(() {
      if (_selectedCharacters.contains(character)) {
        _selectedCharacters.remove(character);
        if (_selectedCharacters.isEmpty) _isMultiSelectMode = false;
      } else {
        _selectedCharacters.add(character);
      }
    });
  }

  void _enterMultiSelectMode(String character) {
    setState(() {
      _isMultiSelectMode = true;
      _selectedCharacters.add(character);
    });
  }

  void _exitMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedCharacters.clear();
    });
  }

  Future<void> _deleteSelectedCharacters() async {
    final count = _selectedCharacters.length;
    final confirmed = await WFDialog.show<bool>(
      context,
      title: '确认删除',
      content: Text('确定要删除选中的 $count 个字符吗？此操作不可撤销。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: WFColors.error),
          child: const Text('删除'),
        ),
      ],
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

  // ═══════════════════════════════════════════════════════════
  // 构建 UI
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final glyphs = widget.project.glyphs;
    final editedCount = glyphs.values.where((g) => g.contours.isNotEmpty).length;

    return Scaffold(
      appBar: _isMultiSelectMode
          ? WFAppBar(
              title: '已选 ${_selectedCharacters.length} 个',
              leading: IconButton(
                onPressed: _exitMultiSelectMode,
                icon: const Icon(Icons.close),
              ),
              actions: [
                IconButton(
                  onPressed: _deleteSelectedCharacters,
                  icon: const Icon(Icons.delete_outline, color: WFColors.error),
                  tooltip: '删除选中',
                ),
              ],
            )
          : WFAppBar(
              title: '字体预览',
              actions: [
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
                  onPressed: () => _showGlyphList(),
                  icon: const Icon(Icons.list),
                  tooltip: '查看字符列表',
                ),
              ],
            ),
      body: Column(
        children: [
          // ── 字体信息头部 ──
          _buildFontInfoHeader(glyphs.length, editedCount),
          // ── 预览输入 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
          // ── 预览区域 ──
          Expanded(
            child: _previewText.isEmpty
                ? const Center(
                    child: Text(
                      '输入文字查看预览效果',
                      style: TextStyle(color: WFColors.textLight, fontSize: 16),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 大字预览
                        _buildPreviewCard('大字预览', 48),
                        const SizedBox(height: 12),
                        // 中字预览
                        _buildPreviewCard('中字预览', 28),
                        const SizedBox(height: 12),
                        // 小字预览
                        _buildPreviewCard('小字预览', 16),
                        const SizedBox(height: 16),
                        // 字符网格
                        _buildCharacterGridSection(glyphs),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  /// 字体信息头部 — WFCard 包裹
  Widget _buildFontInfoHeader(int total, int edited) {
    final project = widget.project;
    final dateStr =
        '${project.createdAt.year}-${project.createdAt.month.toString().padLeft(2, '0')}-${project.createdAt.day.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: WFCard(
        accentColor: WFColors.accent,
        child: Row(
          children: [
            // 左侧：字体名称 & 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: WFColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.text_fields, size: 14, color: WFColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        '$edited / $total 个字符',
                        style: const TextStyle(
                          fontSize: 13,
                          color: WFColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.calendar_today, size: 14, color: WFColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        dateStr,
                        style: const TextStyle(
                          fontSize: 13,
                          color: WFColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 右侧：完成度指示
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: edited == total && total > 0
                    ? WFColors.success.withValues(alpha: 0.12)
                    : WFColors.primary.withValues(alpha: 0.12),
              ),
              child: Center(
                child: Text(
                  total > 0 ? '${(edited * 100 ~/ total)}%' : '0%',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: edited == total && total > 0
                        ? WFColors.success
                        : WFColors.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 预览卡片 — WFCard 包裹
  Widget _buildPreviewCard(String label, double fontSize) {
    return WFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: WFColors.textSecondary),
          ),
          const SizedBox(height: 8),
          _buildGlyphPreviewText(_previewText, fontSize),
        ],
      ),
    );
  }

  /// 构建字形预览文本
  Widget _buildGlyphPreviewText(String text, double fontSize) {
    final List<InlineSpan> spans = [];
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      final glyph = widget.project.glyphs[char];
      if (glyph != null && glyph.contours.isNotEmpty) {
        spans.add(WidgetSpan(
          child: GlyphWidget(
            contours: glyph.contours,
            size: fontSize,
            color: WFColors.textPrimary,
          ),
          alignment: PlaceholderAlignment.middle,
        ));
      } else {
        spans.add(TextSpan(
          text: char,
          style: TextStyle(fontSize: fontSize, color: WFColors.textPrimary),
        ));
      }
    }
    return RichText(text: TextSpan(children: spans));
  }

  /// 字符网格区域 — 使用 WFCard 包裹每个字符
  Widget _buildCharacterGridSection(Map<String, GlyphData> glyphs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '已收录字符',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: WFColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          '点击字符可编辑 · 长按批量选择',
          style: TextStyle(fontSize: 12, color: WFColors.textSecondary.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: 8),
        // 搜索框
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
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (v) => setState(() => _searchQuery = v),
        ),
        const SizedBox(height: 8),
        _buildCharacterGrid(glyphs),
      ],
    );
  }

  /// 字符网格 — 每个字符用 WFCard 包裹，编辑状态用绿色边框
  Widget _buildCharacterGrid(Map<String, GlyphData> glyphs) {
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
        child: const Text(
          '未找到匹配的字符',
          style: TextStyle(color: WFColors.textLight, fontSize: 14),
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
        final isEdited = glyph.contours.isNotEmpty;

        // 边框颜色：已选 > 已编辑（绿色）> 未编辑（灰色）
        final borderColor = isSelected
            ? WFColors.primary
            : isEdited
                ? WFColors.success
                : WFColors.textLight;
        final borderWidth = isSelected ? 2.5 : isEdited ? 1.5 : 1.0;

        return GestureDetector(
          onTap: () => _editCharacter(character, glyph),
          onLongPress: () => _enterMultiSelectMode(character),
          child: Tooltip(
            message: '$unicodeHex · 点击编辑',
            child: Container(
              width: 48,
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor, width: borderWidth),
                color: WFColors.bgCard,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
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
                                color: isSelected ? WFColors.primary : WFColors.textPrimary,
                              )
                            : Center(
                                child: Text(
                                  entry.key,
                                  style: TextStyle(
                                    fontSize: 20,
                                    color: isSelected ? WFColors.primary : WFColors.textPrimary,
                                  ),
                                ),
                              ),
                        // 已编辑标记
                        if (isEdited && !isSelected)
                          Positioned(
                            top: 2,
                            right: 2,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: WFColors.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        // 多选勾选标记
                        if (isSelected)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(1),
                              decoration: const BoxDecoration(
                                color: WFColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check, size: 12, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    unicodeHex.substring(2),
                    style: const TextStyle(
                      fontSize: 8,
                      color: WFColors.textSecondary,
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

  /// 底部操作栏 — WFPrimaryButton 导出
  Widget _buildBottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 保存 & 备份
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSaving ? null : _saveProject,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isSaving ? '保存中...' : '保存项目'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 编辑元数据 + 导出 TTF
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _editMetadata,
                    icon: const Icon(Icons.tune),
                    label: const Text('编辑元数据'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: WFPrimaryButton(
                    text: _isExporting ? '导出中...' : '导出 TTF',
                    icon: _isExporting ? null : Icons.file_download,
                    onPressed: _isExporting ? () {} : _exportFont,
                  ),
                ),
              ],
            ),
            // 元数据状态提示
            if (_fontMetadata != null) ...[
              const SizedBox(height: 8),
              Text(
                '已设置元数据：${_fontMetadata!.familyName} ${_fontMetadata!.subfamilyName}',
                style: const TextStyle(fontSize: 12, color: WFColors.success),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 字符列表底部弹出
  void _showGlyphList() {
    final glyphs = widget.project.glyphs.entries.toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: WFColors.textLight.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '字符列表 (${glyphs.length})',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                                color: WFColors.textPrimary,
                              )
                            : Center(
                                child: Text(entry.key, style: const TextStyle(fontSize: 24)),
                              ),
                      ),
                      title: Text(
                        'U+${entry.value.unicode.toRadixString(16).toUpperCase().padLeft(4, '0')}',
                      ),
                      subtitle: Text('${entry.value.contours.length} 个轮廓'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(entry.key, style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 8),
                          const Icon(Icons.edit, size: 16, color: WFColors.textLight),
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
