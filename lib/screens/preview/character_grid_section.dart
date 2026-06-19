import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glyph_widget.dart';

/// 字符网格区域 — 搜索框 + 字符网格
class CharacterGridSection extends StatelessWidget {
  final Map<String, GlyphData> glyphs;
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final Set<String> selectedCharacters;
  final bool isMultiSelectMode;
  final void Function(String character, GlyphData glyph) onCharacterTap;
  final void Function(String character) onCharacterLongPress;

  const CharacterGridSection({
    super.key,
    required this.glyphs,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.selectedCharacters,
    required this.isMultiSelectMode,
    required this.onCharacterTap,
    required this.onCharacterLongPress,
  });

  @override
  Widget build(BuildContext context) {
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
          controller: searchController,
          decoration: InputDecoration(
            hintText: '搜索字符或 Unicode 编码...',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      searchController.clear();
                      onSearchChanged('');
                    },
                  )
                : null,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: onSearchChanged,
        ),
        const SizedBox(height: 8),
        _buildCharacterGrid(),
      ],
    );
  }

  /// 字符网格 — 每个字符用容器包裹，编辑状态用绿色边框
  Widget _buildCharacterGrid() {
    final filteredEntries = glyphs.entries.where((entry) {
      if (searchQuery.isEmpty) return true;
      final query = searchQuery.toLowerCase();
      final character = entry.key;
      final unicodeHex = entry.value.unicode.toRadixString(16).toUpperCase().padLeft(4, '0');
      return character.toLowerCase().contains(query) ||
          unicodeHex.toLowerCase().contains(query) ||
          'U+$unicodeHex'.toLowerCase().contains(query);
    }).toList();

    if (filteredEntries.isEmpty && searchQuery.isNotEmpty) {
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
        final isSelected = selectedCharacters.contains(character);
        final isEdited = glyph.contours.isNotEmpty;

        // 边框颜色：已选 > 已编辑（绿色）> 未编辑（灰色）
        final borderColor = isSelected
            ? WFColors.primary
            : isEdited
                ? WFColors.success
                : WFColors.textLight;
        final borderWidth = isSelected ? 2.5 : isEdited ? 1.5 : 1.0;

        return GestureDetector(
          onTap: () => onCharacterTap(character, glyph),
          onLongPress: () => onCharacterLongPress(character),
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
}
