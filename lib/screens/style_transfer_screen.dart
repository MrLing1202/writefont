import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/project.dart';
import '../services/font_style_analyzer.dart';
import '../services/style_transfer_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// AI 字体风格迁移页面
///
/// 支持上传参考字体（TTF），分析风格特征，
/// 并将风格应用到已有项目的手写字形上。
class StyleTransferScreen extends StatefulWidget {
  const StyleTransferScreen({super.key});

  @override
  State<StyleTransferScreen> createState() => _StyleTransferScreenState();
}

class _StyleTransferScreenState extends State<StyleTransferScreen> {
  // ── 参考字体状态 ──
  String? _ttfFileName;
  String? _ttfFilePath;
  FontStyleProfile? _fontStyleProfile;

  // ── 项目选择状态 ──
  List<FontProject> _projects = [];
  FontProject? _selectedProject;

  // ── 迁移设置 ──
  double _transferStrength = 50.0;

  // ── 加载状态 ──
  bool _isAnalyzing = false;
  bool _isTransferring = false;
  bool _isLoadingProjects = true;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  /// 加载已有项目列表
  Future<void> _loadProjects() async {
    try {
      final projects = await StorageService.loadProjects();
      if (mounted) {
        setState(() {
          _projects = projects;
          _isLoadingProjects = false;
        });
      }
    } catch (e) {
      debugPrint('加载项目失败: $e');
      if (mounted) {
        setState(() => _isLoadingProjects = false);
      }
    }
  }

  /// 选择 TTF 文件
  Future<void> _pickTtfFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttf'],
        withData: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) {
        if (mounted) {
          WFSnackBar.error(context, '无法获取文件路径');
        }
        return;
      }

      setState(() {
        _ttfFileName = file.name;
        _ttfFilePath = file.path;
        _fontStyleProfile = null;
      });

      // 自动分析字体风格
      await _analyzeFontStyle();
    } catch (e) {
      debugPrint('选择文件失败: $e');
      if (mounted) {
        WFSnackBar.error(context, '选择文件失败');
      }
    }
  }

  /// 分析 TTF 文件的风格特征
  Future<void> _analyzeFontStyle() async {
    if (_ttfFilePath == null) return;

    setState(() => _isAnalyzing = true);

    try {
      final profile = await FontStyleAnalyzer.analyzeTtf(_ttfFilePath!);
      if (mounted) {
        setState(() {
          _fontStyleProfile = profile;
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      debugPrint('风格分析失败: $e');
      if (mounted) {
        setState(() => _isAnalyzing = false);
        WFSnackBar.error(context, '风格分析失败，请重试');
      }
    }
  }

  /// 预览风格迁移效果
  Future<void> _previewTransfer() async {
    if (!_canTransfer()) return;

    if (mounted) {
      WFSnackBar.show(context, '预览功能开发中，敬请期待');
    }
  }

  /// 执行风格迁移
  Future<void> _applyTransfer() async {
    if (!_canTransfer()) return;

    // 确认对话框
    final confirmed = await WFDialog.confirm(
      context,
      title: '确认风格迁移',
      message: '将把参考字体的风格应用到「${_selectedProject!.name}」项目中，'
          '迁移强度 ${_transferStrength.toStringAsFixed(0)}%。'
          '此操作会修改项目的字形数据，建议先备份。',
      icon: Icons.auto_fix_high,
      iconColor: WFColors.warning,
      confirmText: '开始迁移',
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isTransferring = true);

    try {
      final params = StyleTransferParams(
        strength: _transferStrength / 100.0,
      );

      final glyphs = _selectedProject!.glyphs.values.toList();
      final transferred = await StyleTransferService.transferStyle(
        glyphs,
        _fontStyleProfile!,
        params,
      );

      // 更新项目中的字形数据
      for (var i = 0; i < glyphs.length; i++) {
        _selectedProject!.glyphs[glyphs[i].character] = transferred[i];
      }
      _selectedProject!.updatedAt = DateTime.now();

      // 保存项目
      await StorageService.saveProject(_selectedProject!);

      if (mounted) {
        setState(() => _isTransferring = false);
        WFSnackBar.success(context, '风格迁移完成！已更新 ${transferred.length} 个字符');
      }
    } catch (e) {
      debugPrint('风格迁移失败: $e');
      if (mounted) {
        setState(() => _isTransferring = false);
        WFSnackBar.error(context, '风格迁移失败，请重试');
      }
    }
  }

  /// 检查是否满足迁移条件
  bool _canTransfer() {
    return _fontStyleProfile != null &&
        _selectedProject != null &&
        !_isAnalyzing &&
        !_isTransferring;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const WFAppBar(title: '风格迁移'),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 参考字体上传区 ──
                WFAnimations.fadeInSlide(_buildUploadSection()),
                const SizedBox(height: 16),

                // ── 风格特征预览区 ──
                if (_fontStyleProfile != null) ...[
                  WFAnimations.fadeInSlide(
                    _buildStylePreview(),
                    delay: const Duration(milliseconds: 80),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── 迁移设置区 ──
                WFAnimations.fadeInSlide(
                  _buildTransferSettings(),
                  delay: const Duration(milliseconds: 160),
                ),
                const SizedBox(height: 24),

                // ── 操作按钮区 ──
                WFAnimations.fadeInSlide(
                  _buildActionButtons(),
                  delay: const Duration(milliseconds: 240),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),

          // ── 全局加载指示器 ──
          if (_isTransferring)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: Center(
                child: WFCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        color: WFColors.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '正在迁移风格...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: WFColors.textPrimaryColor(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '请稍候，正在处理 ${_selectedProject?.glyphs.length ?? 0} 个字符',
                        style: TextStyle(
                          fontSize: 13,
                          color: WFColors.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建参考字体上传区
  Widget _buildUploadSection() {
    return WFCard(
      accentColor: WFColors.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: WFColors.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.font_download,
                  size: 22,
                  color: WFColors.info,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '参考字体',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: WFColors.textPrimaryColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _ttfFileName ?? '选择 TTF 文件作为风格参考',
                      style: TextStyle(
                        fontSize: 13,
                        color: _ttfFileName != null
                            ? WFColors.success
                            : WFColors.textSecondaryColor(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: WFSecondaryButton(
              text: _ttfFileName == null ? '选择 TTF 文件' : '更换文件',
              onPressed: _pickTtfFile,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建风格特征预览区
  Widget _buildStylePreview() {
    final profile = _fontStyleProfile!;

    return WFCard(
      accentColor: WFColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: WFColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.analytics,
                  size: 22,
                  color: WFColors.accent,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '风格特征',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: WFColors.textPrimaryColor(context),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '从参考字体中提取的风格参数',
                      style: TextStyle(
                        fontSize: 13,
                        color: WFColors.textSecondaryColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 特征参数网格
          Row(
            children: [
              Expanded(
                child: _buildFeatureItem(
                  '笔画粗细',
                  '${profile.averageStrokeWidth.toStringAsFixed(0)} 单位',
                  Icons.line_weight,
                  WFColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFeatureItem(
                  '倾斜角度',
                  '${profile.slantAngle.toStringAsFixed(1)}°',
                  Icons.format_italic,
                  WFColors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildFeatureItem(
                  '连笔风格',
                  '${(profile.connectionStrength * 100).toStringAsFixed(0)}%',
                  Icons.gesture,
                  WFColors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFeatureItem(
                  '宽高比',
                  profile.aspectRatio.toStringAsFixed(2),
                  Icons.aspect_ratio,
                  WFColors.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建单个特征参数项
  Widget _buildFeatureItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: WFColors.textSecondaryColor(context),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建迁移设置区
  Widget _buildTransferSettings() {
    return WFCard(
      accentColor: WFColors.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: WFColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.tune,
                  size: 22,
                  color: WFColors.warning,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '迁移设置',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: WFColors.textPrimaryColor(context),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '选择项目并调整迁移参数',
                      style: TextStyle(
                        fontSize: 13,
                        color: WFColors.textSecondaryColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 项目选择
          const Text(
            '选择项目',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: WFColors.textPrimaryColor(context),
            ),
          ),
          const SizedBox(height: 8),
          _buildProjectDropdown(),
          const SizedBox(height: 20),

          // 迁移强度滑块
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '迁移强度',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: WFColors.textPrimaryColor(context),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: WFColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_transferStrength.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: WFColors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: WFColors.warning,
              inactiveTrackColor: WFColors.warning.withValues(alpha: 0.2),
              thumbColor: WFColors.warning,
              overlayColor: WFColors.warning.withValues(alpha: 0.1),
            ),
            child: Slider(
              value: _transferStrength,
              min: 0,
              max: 100,
              divisions: 20,
              onChanged: (value) {
                setState(() => _transferStrength = value);
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '轻微调整',
                style: TextStyle(
                  fontSize: 12,
                  color: WFColors.textSecondaryColor(context),
                ),
              ),
              Text(
                '强烈迁移',
                style: TextStyle(
                  fontSize: 12,
                  color: WFColors.textSecondaryColor(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建项目选择下拉框
  Widget _buildProjectDropdown() {
    if (_isLoadingProjects) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: WFColors.textLightColor(context)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_projects.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          border: Border.all(color: WFColors.textLightColor(context)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: WFColors.textSecondaryColor(context)),
            SizedBox(width: 8),
            Text(
              '暂无项目，请先创建字体项目',
              style: TextStyle(
                fontSize: 14,
                color: WFColors.textSecondaryColor(context),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: WFColors.textLightColor(context)),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<FontProject>(
          isExpanded: true,
          value: _selectedProject,
          hint: const Text(
            '请选择要迁移的项目',
            style: TextStyle(
              fontSize: 14,
              color: WFColors.textSecondaryColor(context),
            ),
          ),
          items: _projects.map((project) {
            final glyphCount = project.glyphs.values
                .where((g) => g.contours.isNotEmpty)
                .length;
            return DropdownMenuItem<FontProject>(
              value: project,
              child: Row(
                children: [
                  const Icon(
                    Icons.folder,
                    size: 18,
                    color: WFColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      project.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '$glyphCount 字',
                    style: const TextStyle(
                      fontSize: 12,
                      color: WFColors.textSecondaryColor(context),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (project) {
            setState(() => _selectedProject = project);
          },
        ),
      ),
    );
  }

  /// 构建操作按钮区
  Widget _buildActionButtons() {
    final canTransfer = _canTransfer();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WFPrimaryButton(
          text: '应用迁移',
          icon: Icons.auto_fix_high,
          onPressed: canTransfer ? _applyTransfer : null,
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton.icon(
            onPressed: canTransfer ? _previewTransfer : null,
            icon: Icon(
              Icons.preview,
              size: 18,
              color: canTransfer ? WFColors.info : WFColors.textLightColor(context),
            ),
            label: Text(
              '预览效果',
              style: TextStyle(
                color: canTransfer ? WFColors.info : WFColors.textLightColor(context),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
