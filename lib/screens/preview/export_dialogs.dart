import 'package:flutter/material.dart';
import '../../models/project.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glyph_widget.dart';

/// 信息行 — 用于对话框内展示
Widget buildInfoRow(IconData icon, String label, String value) {
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

/// 导出确认对话框（WFDialog 样式）
Future<bool?> showExportConfirmDialog(
  BuildContext context,
  FontProject project,
) async {
  final glyphs = project.glyphs;
  final editedCount = glyphs.values.where((g) => g.contours.isNotEmpty).length;

  return WFDialog.show<bool>(
    context,
    title: '导出字体',
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        buildInfoRow(Icons.font_download, '字体名称', project.name),
        const SizedBox(height: 8),
        buildInfoRow(Icons.text_fields, '已生成字符', '$editedCount / ${glyphs.length}'),
        const SizedBox(height: 8),
        buildInfoRow(Icons.calendar_today, '创建日期',
            '${project.createdAt.year}-${project.createdAt.month.toString().padLeft(2, '0')}-${project.createdAt.day.toString().padLeft(2, '0')}'),
        const SizedBox(height: 16),
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

/// 字体命名对话框
Future<String?> showFontNameDialog(
  BuildContext context,
  FontProject project,
) async {
  final controller = TextEditingController(text: project.name);
  final formKey = GlobalKey<FormState>();

  // 取前 5 个有轮廓的字符用于预览
  final previewGlyphs = project.glyphs.entries
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

/// 导出成功对话框 — 含分享按钮
void showExportSuccessDialog(
  BuildContext context,
  String filePath,
  FontProject project,
) {
  WFDialog.show(
    context,
    title: '导出成功',
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          '共导出 ${project.glyphs.length} 个字符',
          style: const TextStyle(color: WFColors.textSecondary),
        ),
        const SizedBox(height: 12),
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
