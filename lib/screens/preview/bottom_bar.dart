import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 预览页面底部操作栏 — 保存、备份、编辑元数据、导出 TTF、导出 Google Fonts
class PreviewBottomBar extends StatelessWidget {
  final VoidCallback onSave;
  final VoidCallback onExportBackup;
  final VoidCallback onEditMetadata;
  final VoidCallback onExportFont;
  final VoidCallback onExportGoogleFonts;
  final bool isSaving;
  final bool isExporting;
  final String? metadataInfo;

  const PreviewBottomBar({
    super.key,
    required this.onSave,
    required this.onExportBackup,
    required this.onEditMetadata,
    required this.onExportFont,
    required this.onExportGoogleFonts,
    required this.isSaving,
    required this.isExporting,
    this.metadataInfo,
  });

  @override
  Widget build(BuildContext context) {
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
                    onPressed: isSaving ? null : onSave,
                    icon: isSaving
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(isSaving ? '保存中...' : '保存项目'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onExportBackup,
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
                    onPressed: onEditMetadata,
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
                    text: isExporting ? '导出中...' : '导出 TTF',
                    icon: isExporting ? null : Icons.file_download,
                    onPressed: isExporting ? null : onExportFont,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 导出 Google Fonts 格式
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isExporting ? null : onExportGoogleFonts,
                icon: const Icon(Icons.cloud_upload),
                label: const Text('导出 Google Fonts'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            // 元数据状态提示
            if (metadataInfo != null) ...[
              const SizedBox(height: 8),
              Text(
                '已设置元数据：$metadataInfo',
                style: const TextStyle(fontSize: 12, color: WFColors.success),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
