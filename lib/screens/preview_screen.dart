import 'dart:async';
import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'character_edit_screen.dart';
import 'font_metadata_screen.dart';
import 'preview/font_info_header.dart';
import 'preview/preview_area.dart';
import 'preview/character_grid_section.dart';
import 'preview/bottom_bar.dart';
import 'preview/glyph_list_sheet.dart';
import 'preview/preview_text_input.dart';
import 'preview/export_helper.dart';
import 'preview/multi_select_logic.dart';

/// 预览导出页面
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

  /// 导出 TTF 字体
  Future<void> _exportFont() async {
    setState(() => _isExporting = true);
    try {
      if (_fontMetadata != null) {
        await exportFontWithMetadata(context, widget.project, _fontMetadata!);
      } else {
        await exportFontLegacy(context, widget.project);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mapExportError(e.toString())), duration: const Duration(seconds: 4)),
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
      await saveProjectWithFeedback(context, widget.project);
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
      await exportBackupWithFeedback(context, widget.project);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份导出失败: $e')),
        );
      }
    }
  }

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
    if (await showDeleteConfirmDialog(context, count)) {
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
    final glyphs = widget.project.glyphs;
    final editedCount = glyphs.values.where((g) => g.contours.isNotEmpty).length;
    final dateStr =
        '${widget.project.createdAt.year}-${widget.project.createdAt.month.toString().padLeft(2, '0')}-${widget.project.createdAt.day.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: _isMultiSelectMode
          ? buildMultiSelectAppBar(
              selectedCount: _selectedCharacters.length,
              onExit: _exitMultiSelectMode,
              onDelete: _deleteSelectedCharacters,
            )
          : WFAppBar(
              title: '字体预览',
              actions: [
                if (_isAutoSaving)
                  const Padding(padding: EdgeInsets.only(right: 8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                IconButton(
                  onPressed: () => showGlyphListSheet(context, glyphs, _editCharacter),
                  icon: const Icon(Icons.list), tooltip: '查看字符列表',
                ),
              ],
            ),
      body: Column(
        children: [
          // 字体信息头部
          FontInfoHeader(
            fontName: widget.project.name,
            dateStr: dateStr,
            editedCount: editedCount,
            totalCount: glyphs.length,
          ),
          // 预览输入
          PreviewTextInput(
            textController: _textController,
            previewText: _previewText,
            onChanged: (v) => setState(() => _previewText = v),
          ),
          // 预览区域 + 字符网格
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
                        PreviewArea(
                          previewText: _previewText,
                          glyphs: glyphs,
                        ),
                        const SizedBox(height: 16),
                        CharacterGridSection(
                          glyphs: glyphs,
                          searchController: _searchController,
                          searchQuery: _searchQuery,
                          onSearchChanged: (v) => setState(() => _searchQuery = v),
                          selectedCharacters: _selectedCharacters,
                          isMultiSelectMode: _isMultiSelectMode,
                          onCharacterTap: _editCharacter,
                          onCharacterLongPress: _enterMultiSelectMode,
                        ),
                        const SizedBox(height: 100),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: PreviewBottomBar(
        onSave: _saveProject,
        onExportBackup: _exportProjectBackup,
        onEditMetadata: _editMetadata,
        onExportFont: _exportFont,
        isSaving: _isSaving,
        isExporting: _isExporting,
        metadataInfo: _fontMetadata != null
            ? '${_fontMetadata!.familyName} ${_fontMetadata!.subfamilyName}'
            : null,
      ),
    );
  }
}
