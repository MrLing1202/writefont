import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../theme/app_theme.dart';

/// 预览底部工具栏组件
class PreviewToolbar extends StatelessWidget {
  final FontProject? project;
  final String previewText;
  final double fontSize;
  final double lineHeight;
  final int bgColorIndex;
  final bool isExporting;
  final ValueChanged<double> onFontSizeChanged;
  final ValueChanged<double> onLineHeightChanged;
  final ValueChanged<int> onBgColorChanged;
  final VoidCallback onFontSizePreset;
  final VoidCallback onResetZoom;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onExport;
  final VoidCallback onShare;

  const PreviewToolbar({
    super.key,
    required this.project,
    required this.previewText,
    required this.fontSize,
    required this.lineHeight,
    required this.bgColorIndex,
    required this.isExporting,
    required this.onFontSizeChanged,
    required this.onLineHeightChanged,
    required this.onBgColorChanged,
    required this.onFontSizePreset,
    required this.onResetZoom,
    required this.onToggleFullscreen,
    required this.onExport,
    required this.onShare,
  });

  static const _bgColors = [
    Colors.white,
    WFColors.previewDark,
    WFColors.previewGray,
  ];
  static const _bgLabels = ['白', '黑', '灰'];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final charCount = previewText.replaceAll(RegExp(r'\s'), '').length;
    final glyphCount = project != null
        ? previewText.split('').where((c) => project!.glyphs[c]?.contours.isNotEmpty == true).length
        : 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 字号调节
          _buildFontSizeRow(colorScheme),

          // 行距调节
          _buildLineHeightRow(colorScheme),

          // 背景色切换 + 字符统计
          _buildBgColorAndStatsRow(colorScheme, charCount, glyphCount),

          const SizedBox(height: 8),

          // 操作按钮
          _buildActionButtons(colorScheme),
        ],
      ),
    );
  }

  Widget _buildFontSizeRow(ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(Icons.format_size, size: 20, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          '字号',
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
        ),
        Expanded(
          child: Slider(
            value: fontSize,
            min: 12,
            max: 120,
            divisions: 108,
            label: '${fontSize.round()}pt',
            onChanged: onFontSizeChanged,
          ),
        ),
        ...([24, 48, 72, 96].map((size) {
          final isSelected = fontSize.round() == size;
          return Padding(
            padding: const EdgeInsets.only(left: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onFontSizeChanged(size.toDouble()),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primary.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.outlineVariant.withValues(alpha: 0.4),
                    width: isSelected ? 1.5 : 0.5,
                  ),
                ),
                child: Text(
                  '$size',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        })),
      ],
    );
  }

  Widget _buildLineHeightRow(ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(Icons.format_line_spacing, size: 20, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          '行距',
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
        ),
        Expanded(
          child: Slider(
            value: lineHeight,
            min: 1.0,
            max: 3.0,
            divisions: 20,
            label: lineHeight.toStringAsFixed(1),
            onChanged: onLineHeightChanged,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            lineHeight.toStringAsFixed(1),
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildBgColorAndStatsRow(ColorScheme colorScheme, int charCount, int glyphCount) {
    return Row(
      children: [
        Icon(Icons.palette_outlined, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        ...List.generate(3, (i) {
          final isSelected = bgColorIndex == i;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => onBgColorChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primary.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.outlineVariant.withValues(alpha: 0.4),
                    width: isSelected ? 1.5 : 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _bgColors[i],
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _bgLabels[i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.text_fields, size: 14, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                '$charCount 字 · $glyphCount 有字形',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(ColorScheme colorScheme) {
    return Row(
      children: [
        TextButton.icon(
          onPressed: onResetZoom,
          icon: const Icon(Icons.zoom_out_map, size: 18),
          label: const Text('重置缩放'),
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        FilledButton.tonalIcon(
          onPressed: onToggleFullscreen,
          icon: const Icon(Icons.fullscreen, size: 20),
          label: const Text('全屏预览'),
        ),
        const SizedBox(width: 8),
        isExporting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FilledButton.tonalIcon(
                onPressed: onExport,
                icon: const Icon(Icons.font_download, size: 18),
                label: const Text('导出'),
              ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: onShare,
          icon: const Icon(Icons.share, size: 18),
          label: const Text('分享'),
        ),
      ],
    );
  }
}
