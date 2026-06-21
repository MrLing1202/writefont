import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import 'export_dialogs.dart';
import '../font_metadata_screen.dart';

/// 导出格式枚举
enum ExportFormat {
  ttf('TTF', '适用于桌面系统和大多数场景'),
  otf('OTF', '支持更多高级排版特性'),
  woff('WOFF', '适用于网页嵌入，文件更小');

  final String label;
  final String description;
  const ExportFormat(this.label, this.description);
}

/// 导出质量枚举
enum ExportQuality {
  standard('标准', '基本轮廓质量，文件较小'),
  high('高质量', '精细轮廓，推荐用于正式场合'),
  ultra('超高', '最高精度，文件较大');

  final String label;
  final String description;
  const ExportQuality(this.label, this.description);
}

/// 估算导出文件大小（KB）
/// 基于字符数和轮廓复杂度的粗略估算
int estimateExportFileSizeKB(FontProject project, ExportFormat format, ExportQuality quality) {
  final editedCount = project.glyphs.values
      .where((g) => g.contours.isNotEmpty)
      .length;

  // 每个字符的基础大小（KB）
  double basePerGlyph;
  switch (quality) {
    case ExportQuality.standard:
      basePerGlyph = 1.2;
      break;
    case ExportQuality.high:
      basePerGlyph = 2.5;
      break;
    case ExportQuality.ultra:
      basePerGlyph = 4.0;
      break;
  }

  // 格式系数
  double formatFactor;
  switch (format) {
    case ExportFormat.ttf:
      formatFactor = 1.0;
      break;
    case ExportFormat.otf:
      formatFactor = 1.1;
      break;
    case ExportFormat.woff:
      formatFactor = 0.75; // WOFF 有压缩
      break;
  }

  // 头部开销 + 字符数据
  final headerSize = 2.0; // KB
  final totalKB = (headerSize + editedCount * basePerGlyph) * formatFactor;
  return totalKB.ceil().clamp(1, 99999);
}

/// 格式化文件大小显示
String formatFileSize(int kb) {
  if (kb < 1024) return '$kb KB';
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}

/// 显示构建进度对话框（带进度条和取消）
void _showBuildProgress(BuildContext context, {String message = '正在生成字体文件...'}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(message),
                      const SizedBox(height: 4),
                      Text(
                        '请稍候，正在处理字体数据...',
                        style: TextStyle(
                          fontSize: 12,
                          color: WFColors.textSecondaryColor(context),
                        ),
                      ),
                    ],
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

/// 导出 TTF 字体（带元数据）
Future<void> exportFontWithMetadata(
  BuildContext context,
  FontProject project,
  FontMetadata metadata,
) async {
  project.name = metadata.familyName;

  // 显示构建进度
  if (context.mounted) _showBuildProgress(context);

  try {
    final filePath = await StorageService.exportTtf(
      project,
      familyName: metadata.familyName,
      subfamilyName: metadata.subfamilyName,
      version: metadata.version,
      copyright: metadata.copyright,
      description: metadata.description,
    );
    // 关闭进度对话框
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    if (context.mounted) showExportSuccessDialog(context, filePath, project);
  } catch (e) {
    // 关闭进度对话框
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    if (context.mounted) {
      final errorMsg = mapExportError(e.toString());
      WFSnackBar.error(context, errorMsg);
    }
  }
}

/// 导出 TTF 字体（旧流程：先确认再命名）
Future<void> exportFontLegacy(BuildContext context, FontProject project) async {
  final confirmed = await showExportConfirmDialog(context, project);
  if (confirmed != true) return;

  final fontName = await showFontNameDialog(context, project);
  if (fontName == null || fontName.isEmpty) return;

  project.name = fontName;

  // 显示构建进度
  if (context.mounted) _showBuildProgress(context);

  try {
    final filePath = await StorageService.exportTtf(project);
    // 关闭进度对话框
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    if (context.mounted) showExportSuccessDialog(context, filePath, project);
  } catch (e) {
    // 关闭进度对话框
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    if (context.mounted) {
      final errorMsg = mapExportError(e.toString());
      WFSnackBar.error(context, errorMsg);
    }
  }
}

/// 带格式选择的导出流程
/// 显示格式选择 → 质量选择 → 文件大小预估 → 确认 → 导出
Future<void> exportFontWithFormatSelection(
  BuildContext context,
  FontProject project,
) async {
  // 第一步：选择导出格式
  final format = await WFDialog.singleChoice<ExportFormat>(
    context,
    title: '选择导出格式',
    items: ExportFormat.values.toList(),
    itemBuilder: (fmt) => ListTile(
      leading: const Icon(Icons.font_download, color: WFColors.primary),
      title: Text(
        fmt.label,
        style: TextStyle(fontWeight: FontWeight.w600, color: WFColors.textPrimaryColor(context)),
      ),
      subtitle: Text(
        fmt.description,
        style: TextStyle(fontSize: 12, color: WFColors.textSecondaryColor(context)),
      ),
    ),
  );
  if (format == null || !context.mounted) return;

  // 第二步：选择导出质量
  final quality = await WFDialog.singleChoice<ExportQuality>(
    context,
    title: '选择导出质量',
    items: ExportQuality.values.toList(),
    itemBuilder: (q) => ListTile(
      leading: const Icon(Icons.high_quality, color: WFColors.primary),
      title: Text(
        q.label,
        style: TextStyle(fontWeight: FontWeight.w600, color: WFColors.textPrimaryColor(context)),
      ),
      subtitle: Text(
        q.description,
        style: TextStyle(fontSize: 12, color: WFColors.textSecondaryColor(context)),
      ),
    ),
  );
  if (quality == null || !context.mounted) return;

  // 第三步：确认导出（含文件大小预估）
  final estimatedSize = estimateExportFileSizeKB(project, format, quality);
  final editedCount = project.glyphs.values
      .where((g) => g.contours.isNotEmpty)
      .length;

  final confirmed = await WFDialog.confirm(
    context,
    title: '确认导出',
    message: '格式: ${format.label}\n'
        '质量: ${quality.label}\n'
        '字符数: $editedCount\n'
        '预估大小: ${formatFileSize(estimatedSize)}',
    confirmText: '开始导出',
    icon: Icons.file_download,
  );
  if (confirmed != true || !context.mounted) return;

  // 第四步：执行导出
  _showBuildProgress(context, message: '正在生成 ${format.label} 字体文件...');

  try {
    // 根据用户选择的格式调用对应的导出方法
    final String filePath;
    switch (format) {
      case ExportFormat.ttf:
        filePath = await StorageService.exportTtf(project);
      case ExportFormat.otf:
        filePath = await StorageService.exportOtf(project);
      case ExportFormat.woff:
        filePath = await StorageService.exportWoff(project);
    }

    // 关闭进度对话框
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    if (context.mounted) {
      showExportSuccessDialog(context, filePath, project, extraInfo: '格式: ${format.label} · 质量: ${quality.label}');
    }
  } catch (e) {
    // 关闭进度对话框
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    if (context.mounted) {
      final errorMsg = mapExportError(e.toString());
      WFSnackBar.error(context, errorMsg);
    }
  }
}

/// 导出错误消息映射
String mapExportError(String errorStr) {
  if (errorStr.contains('No such file') || errorStr.contains('Permission')) {
    return '导出失败：存储权限不足，请在系统设置中允许存储权限后重试';
  } else if (errorStr.contains('disk') || errorStr.contains('space') || errorStr.contains('full')) {
    return '导出失败：存储空间不足，请清理手机空间后重试';
  } else if (errorStr.contains('timeout') || errorStr.contains('Timeout')) {
    return '导出超时：字体数据量较大，请稍后重试';
  } else if (errorStr.contains('memory') || errorStr.contains('Memory')) {
    return '导出失败：内存不足，请关闭其他应用后重试';
  }
  return '导出失败：请检查字符数据是否完整，或尝试重新生成字体';
}

/// 保存项目并显示提示
Future<void> saveProjectWithFeedback(BuildContext context, FontProject project) async {
  try {
    await StorageService.saveProject(project);
    if (context.mounted) {
      WFSnackBar.success(
        context,
        '项目「${project.name}」已保存',
        action: SnackBarAction(label: '知道了', onPressed: () {}),
      );
    }
  } catch (e) {
    if (context.mounted) {
      WFSnackBar.error(context, '保存失败: $e');
    }
  }
}

/// 导出项目备份并显示提示
Future<void> exportBackupWithFeedback(BuildContext context, FontProject project) async {
  try {
    final filePath = await StorageService.exportProject(project);
    if (context.mounted) {
      WFSnackBar.success(
        context,
        '备份已导出: ${project.name}_backup.json',
        action: SnackBarAction(
          label: '分享',
          onPressed: () => StorageService.shareTtf(filePath),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      WFSnackBar.error(context, '备份导出失败: $e');
    }
  }
}
