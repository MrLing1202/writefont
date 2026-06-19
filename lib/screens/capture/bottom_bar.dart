import 'package:flutter/material.dart';

/// 拍照页面底部操作栏 — 相册、拍照、多选按钮
class CaptureBottomBar extends StatelessWidget {
  final VoidCallback onTakePhoto;
  final VoidCallback onPickFromGallery;
  final VoidCallback onPickMulti;
  final ColorScheme colorScheme;

  const CaptureBottomBar({
    super.key,
    required this.onTakePhoto,
    required this.onPickFromGallery,
    required this.onPickMulti,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 相册选择按钮
            SizedBox(
              width: 64,
              height: 64,
              child: OutlinedButton(
                onPressed: onPickFromGallery,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: EdgeInsets.zero,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.photo_library, size: 24, color: colorScheme.primary),
                    const SizedBox(height: 2),
                    Text(
                      '相册',
                      style: TextStyle(fontSize: 11, color: colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),
            // 大圆形拍照按钮
            SizedBox(
              width: 80,
              height: 80,
              child: ElevatedButton(
                onPressed: onTakePhoto,
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: EdgeInsets.zero,
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  elevation: 4,
                ),
                child: const Icon(Icons.camera_alt, size: 36),
              ),
            ),
            const SizedBox(width: 24),
            // 批量相册选择
            SizedBox(
              width: 64,
              height: 64,
              child: OutlinedButton(
                onPressed: onPickMulti,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: EdgeInsets.zero,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.photo_library_outlined, size: 24, color: colorScheme.primary),
                    const SizedBox(height: 2),
                    Text(
                      '多选',
                      style: TextStyle(fontSize: 11, color: colorScheme.primary),
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
}
