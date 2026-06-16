import 'package:flutter/cupertino.dart';

import '../models/font_project.dart';

/// 字形缩略图组件
class GlyphTile extends StatelessWidget {
  final GlyphData glyph;
  final double size;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const GlyphTile({
    super.key,
    required this.glyph,
    this.size = 80,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: glyph.isIncluded
              ? CupertinoColors.white
              : CupertinoColors.systemGrey5,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? CupertinoColors.activeBlue
                : glyph.isIncluded
                    ? CupertinoColors.systemGrey4
                    : CupertinoColors.systemGrey3,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: CupertinoColors.activeBlue.withOpacity(0.3),
                    blurRadius: 4,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Stack(
          children: [
            // 字符显示
            Center(
              child: glyph.processedImage != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(
                        glyph.processedImage!,
                        width: size - 12,
                        height: size - 12,
                        fit: BoxFit.contain,
                        colorBlendMode: BlendMode.multiply,
                      ),
                    )
                  : Text(
                      glyph.character,
                      style: TextStyle(
                        fontSize: size * 0.5,
                        fontWeight: FontWeight.w500,
                        color: CupertinoColors.label,
                      ),
                    ),
            ),
            // 包含状态标记
            if (!glyph.isIncluded)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: CupertinoColors.systemRed,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    CupertinoIcons.minus,
                    size: 10,
                    color: CupertinoColors.white,
                  ),
                ),
              ),
            // 字符标签
            Positioned(
              bottom: 2,
              left: 0,
              right: 0,
              child: Text(
                glyph.character,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: CupertinoColors.secondaryLabel,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
