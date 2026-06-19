import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import 'export_dialogs.dart';
import '../font_metadata_screen.dart';

/// 导出 TTF 字体（带元数据）
Future<void> exportFontWithMetadata(
  BuildContext context,
  FontProject project,
  FontMetadata metadata,
) async {
  project.name = metadata.familyName;
  final filePath = await StorageService.exportTtf(
    project,
    familyName: metadata.familyName,
    subfamilyName: metadata.subfamilyName,
    version: metadata.version,
    copyright: metadata.copyright,
    description: metadata.description,
  );
  if (context.mounted) showExportSuccessDialog(context, filePath, project);
}

/// 导出 TTF 字体（旧流程：先确认再命名）
Future<void> exportFontLegacy(BuildContext context, FontProject project) async {
  final confirmed = await showExportConfirmDialog(context, project);
  if (confirmed != true) return;

  final fontName = await showFontNameDialog(context, project);
  if (fontName == null || fontName.isEmpty) return;

  project.name = fontName;
  final filePath = await StorageService.exportTtf(project);
  if (context.mounted) showExportSuccessDialog(context, filePath, project);
}

/// 导出错误消息映射
String mapExportError(String errorStr) {
  if (errorStr.contains('No such file') || errorStr.contains('Permission')) {
    return '导出失败：存储权限不足，请在系统设置中允许存储权限后重试';
  } else if (errorStr.contains('disk') || errorStr.contains('space') || errorStr.contains('full')) {
    return '导出失败：存储空间不足，请清理手机空间后重试';
  }
  return '导出失败：请检查字符数据是否完整，或尝试重新生成字体';
}

/// 保存项目并显示提示
Future<void> saveProjectWithFeedback(BuildContext context, FontProject project) async {
  await StorageService.saveProject(project);
  if (context.mounted) {
    WFSnackBar.show(
      context,
      '项目「${project.name}」已保存',
      action: SnackBarAction(label: '知道了', onPressed: () {}),
    );
  }
}

/// 导出项目备份并显示提示
Future<void> exportBackupWithFeedback(BuildContext context, FontProject project) async {
  final filePath = await StorageService.exportProject(project);
  if (context.mounted) {
    WFSnackBar.show(
      context,
      '备份已导出: ${project.name}_backup.json',
      action: SnackBarAction(
        label: '分享',
        onPressed: () => StorageService.shareTtf(filePath),
      ),
    );
  }
}
