import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// 字形间距编辑器页面
///
/// 支持选择两个字形，实时预览组合效果，并通过滑块调整间距值。
/// 调整结果保存到 FontProject.kerningPairs 中，供字体导出时使用。
class KerningEditorScreen extends StatefulWidget {
  final FontProject project;

  const KerningEditorScreen({super.key, required this.project});

  @override
  State<KerningEditorScreen> createState() => _KerningEditorScreenState();
}

class _KerningEditorScreenState extends State<KerningEditorScreen> {
  /// 当前选中的左侧字形字符
  String? _leftGlyph;

  /// 当前选中的右侧字形字符
  String? _rightGlyph;

  /// 当前间距值（-100 到 +100）
  double _kerningValue = 0;

  /// 是否正在保存
  bool _saving = false;

  /// 已排序的字形字符列表
  late List<String> _glyphChars;

  @override
  void initState() {
    super.initState();
    _glyphChars = widget.project.glyphs.keys.toList()..sort();
  }

  /// 获取当前字形对的 key（如 'AB'）
  String get _pairKey {
    if (_leftGlyph == null || _rightGlyph == null) return '';
    return '$_leftGlyph$_rightGlyph';
  }

  /// 当两个字形都选中时，加载已有的间距值
  void _loadKerningValue() {
    final key = _pairKey;
    if (key.isEmpty) return;
    final existing = widget.project.kerningPairs[key];
    setState(() {
      _kerningValue = (existing ?? 0).toDouble();
    });
  }

  /// 保存间距值到项目
  Future<void> _save() async {
    if (_pairKey.isEmpty) return;

    setState(() => _saving = true);
    try {
      final value = _kerningValue.round();
      if (value == 0) {
        // 值为 0 时移除该对，减少数据冗余
        widget.project.kerningPairs.remove(_pairKey);
      } else {
        widget.project.kerningPairs[_pairKey] = value;
      }
      widget.project.updatedAt = DateTime.now();
      await StorageService.saveProject(widget.project);

      if (mounted) {
        WFSnackBar.success(context, '已保存间距: $_pairKey → $value');
      }
    } catch (e) {
      if (mounted) {
        WFSnackBar.error(context, '保存失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('字形间距编辑'),
        actions: [
          // 显示已配置的间距对数量
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '${widget.project.kerningPairs.length} 对',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ),
          ),
        ],
      ),
      body: _glyphChars.isEmpty
          ? _buildEmptyState()
          : Column(
              children: [
                // 上半部分：两个并排的字形选择器
                _buildGlyphSelectors(theme),
                const Divider(height: 1),
                // 中间：预览区
                Expanded(child: _buildPreview(theme)),
                const Divider(height: 1),
                // 底部：间距调整滑块 + 保存按钮
                _buildAdjustPanel(theme),
              ],
            ),
    );
  }

  /// 空状态（项目中没有已编辑的字形）
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.text_fields, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text('暂无已编辑的字形', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text('请先在编辑器中添加字形', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
        ],
      ),
    );
  }

  /// 两个并排的字形选择器
  Widget _buildGlyphSelectors(ThemeData theme) {
    return Container(
      height: 200,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // 左侧字形选择器
          Expanded(
            child: _buildGlyphGrid(
              theme: theme,
              label: '左侧字形',
              selected: _leftGlyph,
              onSelect: (char) {
                setState(() => _leftGlyph = char);
                _loadKerningValue();
              },
            ),
          ),
          // 分隔线
          const VerticalDivider(width: 1),
          // 右侧字形选择器
          Expanded(
            child: _buildGlyphGrid(
              theme: theme,
              label: '右侧字形',
              selected: _rightGlyph,
              onSelect: (char) {
                setState(() => _rightGlyph = char);
                _loadKerningValue();
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 单个字形网格选择器
  Widget _buildGlyphGrid({
    required ThemeData theme,
    required String label,
    required String? selected,
    required ValueChanged<String> onSelect,
  }) {
    return Column(
      children: [
        // 标签
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textSecondaryColor(context),
                ),
              ),
              const Spacer(),
              if (selected != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    selected,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 字形网格
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: _glyphChars.length,
            itemBuilder: (context, index) {
              final char = _glyphChars[index];
              final isSelected = char == selected;
              return GestureDetector(
                onTap: () => onSelect(char),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    char,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? theme.colorScheme.onPrimary
                          : WFColors.textPrimaryColor(context),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 预览区：显示两个字形的组合效果
  Widget _buildPreview(ThemeData theme) {
    if (_leftGlyph == null || _rightGlyph == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              '请从上方各选一个字形',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    // 获取两个字形的 GlyphData
    final leftData = widget.project.glyphs[_leftGlyph!];
    final rightData = widget.project.glyphs[_rightGlyph!];

    // 计算组合宽度：左字宽 + 右字宽 + 间距调整
    final leftWidth = leftData?.advanceWidth ?? 500;
    final rightWidth = rightData?.advanceWidth ?? 500;
    final kerning = _kerningValue.round();

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Text(
                '预览效果',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textSecondaryColor(context),
                ),
              ),
              const Spacer(),
              // 间距值标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: kerning == 0
                      ? Colors.grey.withValues(alpha: 0.15)
                      : (kerning > 0
                          ? WFColors.warning.withValues(alpha: 0.15)
                          : WFColors.info.withValues(alpha: 0.15)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  kerning == 0 ? '默认间距' : '${kerning > 0 ? "+" : ""}$kerning',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kerning == 0
                        ? Colors.grey[600]
                        : (kerning > 0 ? WFColors.warning : WFColors.info),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 字形组合预览
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 大号预览文字
                    Text(
                      '$_leftGlyph$_rightGlyph',
                      style: const TextStyle(fontSize: 72, height: 1.2),
                    ),
                    const SizedBox(height: 16),
                    // 详细参数
                    Text(
                      '左: $_leftGlyph (${leftWidth}u)  |  间距: ${kerning > 0 ? "+" : ""}$kerning  |  右: $_rightGlyph (${rightWidth}u)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '组合总宽: ${leftWidth + rightWidth + kerning}u',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                        fontFamily: 'monospace',
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

  /// 底部调整面板：滑块 + 保存按钮
  Widget _buildAdjustPanel(ThemeData theme) {
    final hasPair = _leftGlyph != null && _rightGlyph != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 滑块标题行
          Row(
            children: [
              const Text(
                '间距调整',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${_kerningValue.round()}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kerningValue.round() == 0
                      ? Colors.grey[600]
                      : theme.colorScheme.primary,
                ),
              ),
              Text(
                ' / 100',
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 滑块
          Row(
            children: [
              Text('紧', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              Expanded(
                child: Slider(
                  value: _kerningValue,
                  min: -100,
                  max: 100,
                  divisions: 200,
                  label: '${_kerningValue.round()}',
                  onChanged: hasPair
                      ? (v) => setState(() => _kerningValue = v)
                      : null,
                ),
              ),
              Text('松', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ],
          ),
          const SizedBox(height: 8),
          // 操作按钮行
          Row(
            children: [
              // 重置按钮
              OutlinedButton.icon(
                onPressed: hasPair && _kerningValue != 0
                    ? () => setState(() => _kerningValue = 0)
                    : null,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重置'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
              const SizedBox(width: 12),
              // 保存按钮
              Expanded(
                child: WFPrimaryButton(
                  text: _saving ? '保存中...' : '保存间距',
                  icon: _saving ? null : Icons.save,
                  onPressed: hasPair && !_saving ? _save : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
