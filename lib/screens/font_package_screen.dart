import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/project.dart';
import '../services/font_package_exporter.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// 字体打包导出屏幕
///
/// 选择要打包的字体项目，预览打包内容，一键导出 ZIP。
class FontPackageScreen extends StatefulWidget {
  /// 初始字体项目（可选）
  final FontProject? initialProject;

  const FontPackageScreen({super.key, this.initialProject});

  @override
  State<FontPackageScreen> createState() => _FontPackageScreenState();
}

class _FontPackageScreenState extends State<FontPackageScreen> {
  List<FontProject> _projects = [];
  FontProject? _selectedProject;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _selectedProject = widget.initialProject;
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await StorageService.loadProjects();
      if (mounted) {
        setState(() {
          _projects = projects.where((p) => p.glyphs.isNotEmpty).toList();
          if (_selectedProject == null && _projects.isNotEmpty) {
            _selectedProject = _projects.first;
          }
        });
      }
    } catch (e) {
      debugPrint('[FontPackage] 加载项目失败: $e');
    }
  }

  /// 执行打包导出
  Future<void> _exportPackage() async {
    if (_selectedProject == null) return;

    setState(() => _isExporting = true);

    try {
      WFSnackBar.show(context, '正在生成字体包...');

      final zipBytes = await FontPackageExporter.exportPackage(_selectedProject!);

      // 保存到临时目录
      final tempDir = await getTemporaryDirectory();
      final familyName =
          _selectedProject!.metadata?.familyName ?? _selectedProject!.name;
      final safeName = familyName.replaceAll(RegExp(r'[^\w\-]'), '_');
      final file = File('${tempDir.path}/${safeName}_package.zip');
      await file.writeAsBytes(zipBytes);

      if (!mounted) return;

      // 分享文件
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '字体打包导出 — $familyName',
        text: '手迹造字 · 字体打包导出（TTF + WOFF + CSS + 样本图）',
      );
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '导出失败: $e');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const WFAppBar(title: '字体打包导出'),
      body: _projects.isEmpty
          ? _buildEmptyState()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 字体选择 ──
                  _buildFontSelector(),
                  const SizedBox(height: 24),

                  // ── 打包内容预览 ──
                  if (_selectedProject != null) ...[
                    _buildPackagePreview(),
                    const SizedBox(height: 24),
                    _buildProjectInfo(),
                    const SizedBox(height: 32),
                    _buildExportButton(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.font_download_off,
              size: 64, color: WFColors.textLightColor(context)),
          const SizedBox(height: 16),
          Text(
            '暂无可打包的字体项目',
            style: TextStyle(
              fontSize: 16,
              color: WFColors.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '请先创建字体项目并完成造字',
            style: TextStyle(
              fontSize: 13,
              color: WFColors.textLightColor(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 字体选择器
  Widget _buildFontSelector() {
    return WFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.font_download, size: 20, color: WFColors.primary),
              const SizedBox(width: 8),
              Text(
                '选择字体',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textPrimaryColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(_projects.length, (i) {
            final project = _projects[i];
            final isSelected = _selectedProject == project;
            final name = project.metadata?.familyName ?? project.name;
            final glyphCount =
                project.glyphs.values.where((g) => g.contours.isNotEmpty).length;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() => _selectedProject = project),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? WFColors.primary
                          : WFColors.textLightColor(context).withValues(alpha: 0.3),
                      width: isSelected ? 2 : 1,
                    ),
                    color: isSelected
                        ? WFColors.primary.withValues(alpha: 0.05)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? WFColors.primary.withValues(alpha: 0.15)
                              : WFColors.textLightColor(context).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.font_download,
                          color: isSelected
                              ? WFColors.primary
                              : WFColors.textSecondaryColor(context),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: WFColors.textPrimaryColor(context),
                              ),
                            ),
                            Text(
                              '$glyphCount 个字形',
                              style: TextStyle(
                                fontSize: 12,
                                color: WFColors.textSecondaryColor(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle,
                            color: WFColors.primary, size: 22),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 打包内容预览
  Widget _buildPackagePreview() {
    final familyName =
        _selectedProject!.metadata?.familyName ?? _selectedProject!.name;
    final safeName = familyName.replaceAll(RegExp(r'[^\w\-]'), '_');

    final items = [
      _PackageItem(
        icon: Icons.description,
        iconColor: const Color(0xFF2ECC71),
        name: '$safeName.ttf',
        description: 'TrueType 字体文件',
        size: '约 ${_estimateSize()} KB',
      ),
      _PackageItem(
        icon: Icons.language,
        iconColor: const Color(0xFF3498DB),
        name: '$safeName.woff',
        description: 'Web Open Font Format',
        size: '约 ${(_estimateSize() * 0.7).toInt()} KB',
      ),
      _PackageItem(
        icon: Icons.code,
        iconColor: const Color(0xFF9B59B6),
        name: '$safeName.css',
        description: 'CSS @font-face 代码',
        size: '~1 KB',
      ),
      _PackageItem(
        icon: Icons.html,
        iconColor: const Color(0xFFE67E22),
        name: 'preview.html',
        description: '字体预览页面',
        size: '~3 KB',
      ),
      _PackageItem(
        icon: Icons.image,
        iconColor: const Color(0xFFE74C3C),
        name: '${safeName}_sample.png',
        description: '字体样本图片',
        size: '~50 KB',
      ),
      _PackageItem(
        icon: Icons.text_snippet,
        iconColor: WFColors.textSecondaryColor(context),
        name: 'README.txt',
        description: '使用说明',
        size: '~1 KB',
      ),
    ];

    return WFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2, size: 20, color: WFColors.primary),
              const SizedBox(width: 8),
              Text(
                '打包内容',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textPrimaryColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: item.iconColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(item.icon, size: 18, color: item.iconColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: WFColors.textPrimaryColor(context),
                            ),
                          ),
                          Text(
                            item.description,
                            style: TextStyle(
                              fontSize: 11,
                              color: WFColors.textSecondaryColor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      item.size,
                      style: TextStyle(
                        fontSize: 12,
                        color: WFColors.textLightColor(context),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  /// 项目信息卡片
  Widget _buildProjectInfo() {
    final project = _selectedProject!;
    final name = project.metadata?.familyName ?? project.name;
    final glyphCount =
        project.glyphs.values.where((g) => g.contours.isNotEmpty).length;
    final totalCount = project.glyphs.length;

    return WFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 20, color: WFColors.info),
              const SizedBox(width: 8),
              Text(
                '项目信息',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textPrimaryColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow('字体名称', name),
          _buildInfoRow('已编辑字形', '$glyphCount / $totalCount'),
          if (project.metadata?.author != null &&
              project.metadata!.author!.isNotEmpty)
            _buildInfoRow('作者', project.metadata!.author!),
          if (project.metadata?.version != null)
            _buildInfoRow('版本', project.metadata!.version!),
          _buildInfoRow(
            '创建时间',
            '${project.createdAt.year}/${project.createdAt.month}/${project.createdAt.day}',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: WFColors.textSecondaryColor(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: WFColors.textPrimaryColor(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 导出按钮
  Widget _buildExportButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _isExporting ? null : _exportPackage,
        icon: _isExporting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.archive),
        label: Text(_isExporting ? '正在打包...' : '一键导出 ZIP'),
        style: ElevatedButton.styleFrom(
          backgroundColor: WFColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  /// 估算 TTF 文件大小（粗略）
  int _estimateSize() {
    if (_selectedProject == null) return 0;
    final glyphCount =
        _selectedProject!.glyphs.values.where((g) => g.contours.isNotEmpty).length;
    // 每个字形约 200-500 字节，加上头部开销
    return (glyphCount * 350 + 4096) ~/ 1024;
  }
}

/// 打包内容条目
class _PackageItem {
  final IconData icon;
  final Color iconColor;
  final String name;
  final String description;
  final String size;

  const _PackageItem({
    required this.icon,
    required this.iconColor,
    required this.name,
    required this.description,
    required this.size,
  });
}
