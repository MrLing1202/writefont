import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// 功能入口条目数据
class _EntryItem {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int badge; // 角标数字，0 表示不显示

  const _EntryItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge = 0,
  });
}

/// 首页功能入口卡片 — 分组网格布局
///
/// 22 个功能分为 4 组，每组可折叠：
/// - 📝 创建：拍照导入、批量导入、手写模板、练习模式
/// - 👁 预览：字体预览、增强预览、自定义文本预览、字体对比
/// - 🔧 编辑：字符总览、字形间距、智能推荐、字形质量、风格迁移、笔画顺序
/// - 📦 导出：字体家族、网页导出、Google Fonts导出、字符集分析、字形补全、我的字体、字体测试套件、字体打包导出
class SecondaryEntryCard extends StatefulWidget {
  final int savedProjectCount;

  // ── 创建 ──
  final VoidCallback onCameraImportTap;
  final VoidCallback onBatchImportTap;
  final VoidCallback onTemplateGeneratorTap;
  final VoidCallback onPracticeModeTap;

  // ── 预览 ──
  final VoidCallback onFontPreviewTap;
  final VoidCallback onEnhancedPreviewTap;
  final VoidCallback onTextPreviewTap;
  final VoidCallback onFontCompareTap;

  // ── 编辑 ──
  final VoidCallback onCharGridTap;
  final VoidCallback onKerningEditorTap;
  final VoidCallback onCharRecommendTap;
  final VoidCallback onGlyphQualityTap;
  final VoidCallback onStyleTransferTap;
  final VoidCallback onStrokeOrderTap;

  // ── 导出 ──
  final VoidCallback onFontFamilyTap;
  final VoidCallback onWebExportTap;
  final VoidCallback onGoogleFontsExportTap;
  final VoidCallback onCharsetAnalysisTap;
  final VoidCallback onGlyphCompletionTap;
  final VoidCallback onMyFontsTap;

  // ── 高级 ──
  final VoidCallback onFontTestSuiteTap;
  final VoidCallback onFontPackageTap;

  const SecondaryEntryCard({
    super.key,
    required this.savedProjectCount,
    required this.onCameraImportTap,
    required this.onBatchImportTap,
    required this.onTemplateGeneratorTap,
    required this.onPracticeModeTap,
    required this.onFontPreviewTap,
    required this.onEnhancedPreviewTap,
    required this.onTextPreviewTap,
    required this.onFontCompareTap,
    required this.onCharGridTap,
    required this.onKerningEditorTap,
    required this.onCharRecommendTap,
    required this.onGlyphQualityTap,
    required this.onStyleTransferTap,
    required this.onStrokeOrderTap,
    required this.onFontFamilyTap,
    required this.onWebExportTap,
    required this.onGoogleFontsExportTap,
    required this.onCharsetAnalysisTap,
    required this.onGlyphCompletionTap,
    required this.onMyFontsTap,
    required this.onFontTestSuiteTap,
    required this.onFontPackageTap,
  });

  @override
  State<SecondaryEntryCard> createState() => _SecondaryEntryCardState();
}

class _SecondaryEntryCardState extends State<SecondaryEntryCard> {
  /// 各组展开状态：创建、预览默认展开，编辑、导出默认折叠
  final _expanded = [true, true, false, false];

  @override
  Widget build(BuildContext context) {
    return WFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGroup(
            context,
            index: 0,
            emoji: '📝',
            title: '创建',
            entries: [
              _EntryItem(
                icon: Icons.camera_alt,
                iconColor: WFColors.success,
                title: '拍照导入',
                subtitle: '拍照即识别生成字体',
                onTap: widget.onCameraImportTap,
              ),
              _EntryItem(
                icon: Icons.burst_mode_outlined,
                iconColor: const Color(0xFF00897B),
                title: '批量导入',
                subtitle: '多张照片一键识别',
                onTap: widget.onBatchImportTap,
              ),
              _EntryItem(
                icon: Icons.grid_on,
                iconColor: WFColors.primary,
                title: '手写模板',
                subtitle: '生成可打印方格纸模板',
                onTap: widget.onTemplateGeneratorTap,
              ),
              _EntryItem(
                icon: Icons.edit_note,
                iconColor: WFColors.success,
                title: '练习模式',
                subtitle: '针对弱字反复练习',
                onTap: widget.onPracticeModeTap,
              ),
            ],
          ),
          _buildGroup(
            context,
            index: 1,
            emoji: '👁',
            title: '预览',
            entries: [
              _EntryItem(
                icon: Icons.visibility,
                iconColor: WFColors.accent,
                title: '字体预览',
                subtitle: '输入文字查看手迹效果',
                onTap: widget.onFontPreviewTap,
              ),
              _EntryItem(
                icon: Icons.dashboard_customize,
                iconColor: WFColors.info,
                title: '增强预览',
                subtitle: '多字号 · 多场景 · 实时对比',
                onTap: widget.onEnhancedPreviewTap,
              ),
              _EntryItem(
                icon: Icons.text_snippet,
                iconColor: const Color(0xFF3498DB),
                title: '自定义文本',
                subtitle: '输入任意文字查看效果',
                onTap: widget.onTextPreviewTap,
              ),
              _EntryItem(
                icon: Icons.compare,
                iconColor: WFColors.accent,
                title: '字体对比',
                subtitle: '多字体并排预览对比',
                onTap: widget.onFontCompareTap,
              ),
            ],
          ),
          _buildGroup(
            context,
            index: 2,
            emoji: '🔧',
            title: '编辑',
            entries: [
              _EntryItem(
                icon: Icons.dashboard,
                iconColor: WFColors.success,
                title: '字符总览',
                subtitle: '查看造字进度',
                onTap: widget.onCharGridTap,
              ),
              _EntryItem(
                icon: Icons.space_bar,
                iconColor: WFColors.primary,
                title: '字形间距',
                subtitle: '调整字形对之间的间距',
                onTap: widget.onKerningEditorTap,
              ),
              _EntryItem(
                icon: Icons.recommend,
                iconColor: WFColors.warning,
                title: '智能推荐',
                subtitle: '查看待写字符与完成进度',
                onTap: widget.onCharRecommendTap,
              ),
              _EntryItem(
                icon: Icons.assessment,
                iconColor: const Color(0xFF9B59B6),
                title: '字形质量',
                subtitle: '四维评分 · 发现待改进字形',
                onTap: widget.onGlyphQualityTap,
              ),
              _EntryItem(
                icon: Icons.auto_fix_high,
                iconColor: WFColors.warning,
                title: '风格迁移',
                subtitle: 'AI 智能字体风格转换',
                onTap: widget.onStyleTransferTap,
              ),
              _EntryItem(
                icon: Icons.brush,
                iconColor: const Color(0xFFE67E22),
                title: '笔画顺序',
                subtitle: '演示汉字书写笔画顺序',
                onTap: widget.onStrokeOrderTap,
              ),
            ],
          ),
          _buildGroup(
            context,
            index: 3,
            emoji: '📦',
            title: '导出',
            entries: [
              _EntryItem(
                icon: Icons.font_download,
                iconColor: const Color(0xFF2ECC71),
                title: '字体家族',
                subtitle: '一键生成 Bold · Italic 变体',
                onTap: widget.onFontFamilyTap,
              ),
              _EntryItem(
                icon: Icons.language,
                iconColor: WFColors.info,
                title: '网页导出',
                subtitle: '生成 @font-face CSS · HTML',
                onTap: widget.onWebExportTap,
              ),
              _EntryItem(
                icon: Icons.cloud_upload,
                iconColor: const Color(0xFF4285F4),
                title: 'Google Fonts',
                subtitle: '导出为 Google Fonts 格式',
                onTap: widget.onGoogleFontsExportTap,
              ),
              _EntryItem(
                icon: Icons.pie_chart,
                iconColor: const Color(0xFF1ABC9C),
                title: '字符集分析',
                subtitle: 'GB2312 覆盖率统计',
                onTap: widget.onCharsetAnalysisTap,
              ),
              _EntryItem(
                icon: Icons.auto_fix_high,
                iconColor: const Color(0xFFE74C3C),
                title: '字形补全',
                subtitle: '笔画模板组合生成缺失字形',
                onTap: widget.onGlyphCompletionTap,
              ),
              _EntryItem(
                icon: Icons.folder_special,
                iconColor: WFColors.info,
                title: '我的字体',
                subtitle: widget.savedProjectCount > 0
                    ? '已保存 ${widget.savedProjectCount} 个字体项目'
                    : '查看和管理已保存的字体项目',
                onTap: widget.onMyFontsTap,
                badge: widget.savedProjectCount,
              ),
              _EntryItem(
                icon: Icons.science_outlined,
                iconColor: const Color(0xFF00BCD4),
                title: '字体测试套件',
                subtitle: '多场景 · 多字号 · 多字重预览',
                onTap: widget.onFontTestSuiteTap,
              ),
              _EntryItem(
                icon: Icons.archive,
                iconColor: const Color(0xFF795548),
                title: '字体打包导出',
                subtitle: 'TTF + WOFF + CSS 一键打包',
                onTap: widget.onFontPackageTap,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建一个可折叠的功能分组
  Widget _buildGroup(
    BuildContext context, {
    required int index,
    required String emoji,
    required String title,
    required List<_EntryItem> entries,
  }) {
    final isExpanded = _expanded[index];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 分组标题栏（点击折叠/展开）──
        InkWell(
          onTap: () => setState(() => _expanded[index] = !_expanded[index]),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: WFColors.textPrimaryColor(context),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: WFColors.textLightColor(context).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${entries.length}',
                    style: TextStyle(
                      fontSize: 11,
                      color: WFColors.textSecondaryColor(context),
                    ),
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.expand_more,
                    color: WFColors.textSecondaryColor(context),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── 网格内容（带折叠动画）──
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.95,
                crossAxisSpacing: 8,
                mainAxisSpacing: 4,
              ),
              itemCount: entries.length,
              itemBuilder: (ctx, i) => _buildGridItem(ctx, entries[i]),
            ),
          ),
          crossFadeState:
              isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),

        // ── 分组间分隔线 ──
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Divider(
              height: 1,
              color: WFColors.textLightColor(context).withValues(alpha: 0.3),
            ),
          ),
      ],
    );
  }

  /// 构建单个网格图标项
  Widget _buildGridItem(BuildContext context, _EntryItem entry) {
    return InkWell(
      onTap: entry.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 图标容器 ──
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: entry.iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(entry.icon, size: 24, color: entry.iconColor),
                ),
                // ── 角标（如我的字体的数量）──
                if (entry.badge > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: WFColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${entry.badge}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // ── 标题 ──
            Text(
              entry.title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: WFColors.textPrimaryColor(context),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            // ── 副标题 ──
            Text(
              entry.subtitle,
              style: TextStyle(
                fontSize: 10,
                color: WFColors.textSecondaryColor(context),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
