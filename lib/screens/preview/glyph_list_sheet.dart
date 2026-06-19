import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glyph_widget.dart';

/// 字符列表底部弹出
void showGlyphListSheet(
  BuildContext context,
  Map<String, GlyphData> glyphs,
  void Function(String character, GlyphData glyph) onEdit,
) {
  final entries = glyphs.entries.toList();
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
                color: WFColors.textLightColor(context).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '字符列表 (${entries.length})',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return ListTile(
                    onTap: () {
                      Navigator.pop(context);
                      onEdit(entry.key, entry.value);
                    },
                    leading: SizedBox(
                      width: 40,
                      height: 40,
                      child: entry.value.contours.isNotEmpty
                          ? GlyphWidget(
                              contours: entry.value.contours,
                              size: 32,
                              color: WFColors.textPrimaryColor(context),
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
                        Icon(Icons.edit, size: 16, color: WFColors.textLightColor(context)),
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
