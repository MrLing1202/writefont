import 'package:flutter/material.dart';
import '../models/project.dart';
import '../theme/app_theme.dart';
import '../widgets/glyph_widget.dart';
// FontMetadata is now in project.dart

/// 字体元数据编辑页面
///
/// 用户在导出 TTF 之前可以编辑字体的元数据信息，
/// 包括字体族名、子族名、版本号、版权信息和描述。
class FontMetadataScreen extends StatefulWidget {
  final FontProject project;

  const FontMetadataScreen({super.key, required this.project});

  @override
  State<FontMetadataScreen> createState() => _FontMetadataScreenState();
}

class _FontMetadataScreenState extends State<FontMetadataScreen> {
  final _formKey = GlobalKey<FormState>();

  // 元数据字段控制器
  final TextEditingController _familyNameController = TextEditingController();
  final TextEditingController _versionController = TextEditingController();
  final TextEditingController _copyrightController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _authorController = TextEditingController();
  final TextEditingController _licenseController = TextEditingController();

  // 字体子族名下拉选项
  String _subfamilyName = 'Regular';
  static const _subfamilyOptions = ['Regular', 'Bold', 'Light', 'Medium', 'Italic', 'Bold Italic'];

  @override
  void initState() {
    super.initState();
    // 从项目已保存的元数据恢复（如有）
    final saved = widget.project.metadata;
    _familyNameController.text = saved?.familyName ?? widget.project.name;
    _versionController.text = saved?.version ?? 'Version 1.0';
    _copyrightController.text = saved?.copyright ?? '';
    _descriptionController.text = saved?.description ?? '';
    _authorController.text = saved?.author ?? '';
    _licenseController.text = saved?.license ?? '';
    if (saved != null) {
      _subfamilyName = saved.subfamilyName;
    }
  }

  @override
  void dispose() {
    _familyNameController.dispose();
    _versionController.dispose();
    _copyrightController.dispose();
    _descriptionController.dispose();
    _authorController.dispose();
    _licenseController.dispose();
    super.dispose();
  }

  /// 获取已编辑的字符数
  int get _editedGlyphCount =>
      widget.project.glyphs.values.where((g) => g.contours.isNotEmpty).length;

  /// 生成默认文件名
  String get _defaultFileName {
    final name = _familyNameController.text.trim();
    if (name.isEmpty) return '字体.ttf';
    return '${name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')}.ttf';
  }

  /// 导出字体 — 验证后返回元数据给调用方
  void _exportFont() {
    if (!_formKey.currentState!.validate()) return;

    final metadata = FontMetadata(
      familyName: _familyNameController.text.trim(),
      subfamilyName: _subfamilyName,
      version: _versionController.text.trim(),
      copyright: _copyrightController.text.trim(),
      description: _descriptionController.text.trim(),
      author: _authorController.text.trim(),
      license: _licenseController.text.trim(),
    );

    // 确认导出
    _showExportConfirm(metadata);
  }

  /// 显示导出确认对话框
  Future<void> _showExportConfirm(FontMetadata metadata) async {
    final confirmed = await WFDialog.show<bool>(
      context,
      title: '确认导出',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildInfoRow(Icons.font_download, '字体族名', metadata.familyName),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.category, '子族名', metadata.subfamilyName),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.text_fields, '包含字符', '${_editedGlyphCount} 个'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.insert_drive_file, '文件名', _defaultFileName),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: WFColors.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: WFColors.info.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: WFColors.info),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '导出后可在电脑或手机上安装该 TTF 字体文件。',
                    style: TextStyle(fontSize: 12, color: WFColors.textSecondaryColor(context)),
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
          text: '导出字体',
          icon: Icons.file_download,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );

    if (confirmed == true && mounted) {
      // 保存元数据到项目
      widget.project.metadata = metadata;
      Navigator.pop(context, metadata);
    }
  }

  /// 信息行组件
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: WFColors.textSecondaryColor(context)),
        const SizedBox(width: 8),
        Text(
          '$label：',
          style: TextStyle(fontSize: 13, color: WFColors.textSecondaryColor(context)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: WFColors.textPrimaryColor(context),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const WFAppBar(title: '字体元数据编辑'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── 预览区域 ──
            _buildPreviewCard(),
            const SizedBox(height: 16),

            // ── 基本信息 ──
            _buildBasicInfoCard(),
            const SizedBox(height: 16),

            // ── 可选信息 ──
            _buildOptionalInfoCard(),
            const SizedBox(height: 16),

            // ── 导出设置 ──
            _buildExportInfoCard(),
            const SizedBox(height: 24),

            // ── 导出按钮 ──
            WFPrimaryButton(
              text: '导出字体',
              icon: Icons.file_download,
              onPressed: _exportFont,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// 预览卡片 — 显示当前字体族名的渲染效果
  Widget _buildPreviewCard() {
    // 取前 6 个有轮廓的字符用于预览
    final previewGlyphs = widget.project.glyphs.entries
        .where((e) => e.value.contours.isNotEmpty)
        .take(6)
        .toList();

    return WFCard(
      accentColor: WFColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.preview, size: 18, color: WFColors.primary),
              SizedBox(width: 6),
              Text(
                '字体预览',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textSecondaryColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 字体族名显示
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _familyNameController,
            builder: (context, value, _) {
              return Text(
                value.text.isEmpty ? '字体名称' : value.text,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: WFColors.textPrimaryColor(context),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            _subfamilyName,
            style: TextStyle(
              fontSize: 14,
              color: WFColors.textSecondaryColor(context),
            ),
          ),
          if (previewGlyphs.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: previewGlyphs.map((entry) {
                return Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: WFColors.textLightColor(context)),
                    color: WFColors.bgPrimaryColor(context),
                  ),
                  child: Center(
                    child: GlyphWidget(
                      contours: entry.value.contours,
                      size: 36,
                      color: WFColors.textPrimaryColor(context),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  /// 基本信息卡片
  Widget _buildBasicInfoCard() {
    return WFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit, size: 18, color: WFColors.primary),
              SizedBox(width: 6),
              Text(
                '基本信息',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textSecondaryColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 字体族名
          TextFormField(
            controller: _familyNameController,
            decoration: InputDecoration(
              labelText: '字体族名 (Family Name)',
              hintText: '例如：我的手写体',
              prefixIcon: const Icon(Icons.font_download),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '请输入字体族名';
              }
              if (RegExp(r'[<>:"/\\|?*]').hasMatch(value)) {
                return '名称不能包含特殊字符';
              }
              return null;
            },
            maxLength: 50,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),

          // 字体子族名
          DropdownButtonFormField<String>(
            value: _subfamilyName,
            decoration: InputDecoration(
              labelText: '字体子族名 (Subfamily)',
              prefixIcon: const Icon(Icons.category),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            items: _subfamilyOptions.map((option) {
              return DropdownMenuItem(value: option, child: Text(option));
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _subfamilyName = value);
              }
            },
          ),
          const SizedBox(height: 16),

          // 版本号
          TextFormField(
            controller: _versionController,
            decoration: InputDecoration(
              labelText: '版本号 (Version)',
              hintText: '例如：Version 1.0',
              prefixIcon: const Icon(Icons.info_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '请输入版本号';
              }
              return null;
            },
            textInputAction: TextInputAction.next,
          ),
        ],
      ),
    );
  }

  /// 可选信息卡片
  Widget _buildOptionalInfoCard() {
    return WFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info, size: 18, color: WFColors.textSecondaryColor(context)),
              SizedBox(width: 6),
              Text(
                '可选信息',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textSecondaryColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 版权信息
          TextFormField(
            controller: _copyrightController,
            decoration: InputDecoration(
              labelText: '版权信息 (Copyright)',
              hintText: '例如：Copyright 2024 Your Name',
              prefixIcon: const Icon(Icons.copyright),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            maxLength: 100,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),

          // 描述
          TextFormField(
            controller: _descriptionController,
            decoration: InputDecoration(
              labelText: '描述 (Description)',
              hintText: '例如：手写风格个性化字体',
              prefixIcon: const Icon(Icons.description),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            maxLength: 200,
            maxLines: 2,
            textInputAction: TextInputAction.done,
          ),
        ],
      ),
    );
  }

  /// 导出设置信息卡片
  Widget _buildExportInfoCard() {
    return WFCard(
      accentColor: WFColors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.settings, size: 18, color: WFColors.success),
              SizedBox(width: 6),
              Text(
                '导出设置',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textSecondaryColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 文件名预览
          _buildInfoRow(Icons.insert_drive_file, '文件名', _defaultFileName),
          const SizedBox(height: 8),

          // 包含字符数
          _buildInfoRow(Icons.text_fields, '包含字符', '$_editedGlyphCount 个'),
        ],
      ),
    );
  }
}

// FontMetadata class moved to models/project.dart
