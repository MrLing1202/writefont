import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/project.dart';
import '../theme/app_theme.dart';

/// 网页导出页面
///
/// 生成 @font-face CSS、HTML 使用示例、Flutter TextStyle 代码，
/// 并提供自定义文本实时预览。
class WebExportScreen extends StatefulWidget {
  /// 字体项目数据
  final FontProject project;

  const WebExportScreen({super.key, required this.project});

  @override
  State<WebExportScreen> createState() => _WebExportScreenState();
}

class _WebExportScreenState extends State<WebExportScreen> {
  /// 自定义预览文本
  final TextEditingController _previewController = TextEditingController(
    text: '手迹造字 WriteFont',
  );

  /// 当前选色（用于预览字体颜色）
  Color _previewColor = WFColors.textPrimary;

  /// 预设文本列表
  static const _presetTexts = [
    '手迹造字 WriteFont',
    '天地玄黄 宇宙洪荒',
    '永字八法 AaBbCc',
    'Hello 你好世界',
  ];

  /// 可选预览颜色
  static const _previewColors = [
    Color(0xFF2C3E50),
    Color(0xFFE74C3C),
    Color(0xFF2980B9),
    Color(0xFF27AE60),
    Color(0xFFF39C12),
    Color(0xFF8E44AD),
  ];

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }

  /// 获取字体名称（用于代码生成）
  String get _fontName => widget.project.name;

  /// 获取已编辑的字符数量
  int get _editedCount => widget.project.glyphs.values
      .where((g) => g.contours.isNotEmpty)
      .length;

  /// 复制文本到剪贴板并提示
  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      WFSnackBar.success(context, '$label 已复制到剪贴板');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 代码生成
  // ═══════════════════════════════════════════════════════════

  /// 生成 @font-face CSS 代码
  String _buildFontFaceCSS() {
    return '''/* $_fontName — @font-face 声明 */
/* 将字体文件放在项目根目录下的 fonts/ 文件夹中 */

@font-face {
  font-family: '$_fontName';
  src: url('fonts/${_fontFileName('woff2')}') format('woff2'),
       url('fonts/${_fontFileName('woff')}') format('woff'),
       url('fonts/${_fontFileName('ttf')}') format('truetype');
  font-weight: normal;
  font-style: normal;
  font-display: swap;
}''';
  }

  /// 生成 HTML 使用示例代码
  String _buildHTMLExample() {
    return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <title>$_fontName 示例</title>
  <style>
    /* 引入字体 */
    @font-face {
      font-family: '$_fontName';
      src: url('fonts/${_fontFileName('woff2')}') format('woff2'),
           url('fonts/${_fontFileName('woff')}') format('woff'),
           url('fonts/${_fontFileName('ttf')}') format('truetype');
      font-weight: normal;
      font-style: normal;
      font-display: swap;
    }

    .custom-font {
      font-family: '$_fontName', sans-serif;
      font-size: 32px;
      line-height: 1.5;
      color: #2C3E50;
    }
  </style>
</head>
<body>
  <p class="custom-font">手迹造字 WriteFont</p>
  <p class="custom-font">天地玄黄 宇宙洪荒</p>
</body>
</html>''';
  }

  /// 生成 Flutter TextStyle 代码
  String _buildFlutterCode() {
    return '''// pubspec.yaml 中添加字体配置：
// flutter:
//   fonts:
//     - family: $_fontName
//       fonts:
//         - asset: assets/fonts/${_fontFileName('ttf')}

// 使用示例
Text(
  '手迹造字',
  style: TextStyle(
    fontFamily: '$_fontName',
    fontSize: 32,
    height: 1.5,
    color: Color(0xFF2C3E50),
  ),
)

// 或在 ThemeData 中全局设置
ThemeData(
  textTheme: TextTheme(
    bodyLarge: TextStyle(
      fontFamily: '$_fontName',
      fontSize: 16,
    ),
  ),
)''';
  }

  /// 根据格式生成字体文件名
  String _fontFileName(String format) {
    // 将项目名称中的空格替换为下划线，移除特殊字符
    final safeName = _fontName
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^\w一-鿿-]'), '');
    return '$safeName.$format';
  }

  // ═══════════════════════════════════════════════════════════
  // 构建
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const WFAppBar(title: '网页导出'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 项目信息概览
            _buildProjectInfo(),
            const SizedBox(height: 16),

            // @font-face CSS 代码
            _buildCodeSection(
              title: '@font-face CSS',
              icon: Icons.css,
              code: _buildFontFaceCSS(),
              onCopy: () => _copyToClipboard(
                _buildFontFaceCSS(),
                'CSS 代码',
              ),
            ),
            const SizedBox(height: 16),

            // HTML 使用示例
            _buildCodeSection(
              title: 'HTML 使用示例',
              icon: Icons.html,
              code: _buildHTMLExample(),
              onCopy: () => _copyToClipboard(
                _buildHTMLExample(),
                'HTML 代码',
              ),
            ),
            const SizedBox(height: 16),

            // Flutter TextStyle 代码
            _buildCodeSection(
              title: 'Flutter TextStyle',
              icon: Icons.flutter_dash,
              code: _buildFlutterCode(),
              onCopy: () => _copyToClipboard(
                _buildFlutterCode(),
                'Flutter 代码',
              ),
            ),
            const SizedBox(height: 16),

            // 自定义文本预览
            _buildPreviewSection(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// 构建项目信息概览卡片
  Widget _buildProjectInfo() {
    return WFCard(
      accentColor: WFColors.info,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: WFColors.info.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.language,
              color: WFColors.info,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fontName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: WFColors.textPrimaryColor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '已编辑 $_editedCount 个字符 · 支持 WOFF2 / WOFF / TTF',
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
    );
  }

  /// 构建代码区块（标题 + 代码 + 复制按钮）
  Widget _buildCodeSection({
    required String title,
    required IconData icon,
    required String code,
    required VoidCallback onCopy,
  }) {
    return WFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Icon(icon, size: 20, color: WFColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: WFColors.textPrimaryColor(context),
                  ),
                ),
              ),
              // 复制按钮
              TextButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('复制'),
                style: TextButton.styleFrom(
                  foregroundColor: WFColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 代码显示区域
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: WFColors.bgDark,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.6,
                  color: Color(0xFFE0E0E0),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建自定义文本预览区域
  Widget _buildPreviewSection() {
    return WFCard(
      accentColor: WFColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Row(
            children: [
              const Icon(Icons.preview, size: 20, color: WFColors.accent),
              const SizedBox(width: 8),
              Text(
                '自定义文本预览',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textPrimaryColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 预设文本快捷按钮
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presetTexts.map((text) {
              return ActionChip(
                label: Text(
                  text,
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: WFColors.bgPrimaryColor(context),
                side: BorderSide(
                  color: WFColors.textLightColor(context),
                  width: 0.5,
                ),
                onPressed: () {
                  _previewController.text = text;
                  setState(() {});
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // 输入框
          TextField(
            controller: _previewController,
            decoration: InputDecoration(
              hintText: '输入自定义文本…',
              hintStyle: TextStyle(
                color: WFColors.textLightColor(context),
              ),
              prefixIcon: const Icon(Icons.edit, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: WFColors.textLightColor(context),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: WFColors.primary,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          // 颜色选择
          Row(
            children: [
              Text(
                '预览颜色',
                style: TextStyle(
                  fontSize: 13,
                  color: WFColors.textSecondaryColor(context),
                ),
              ),
              const SizedBox(width: 12),
              ..._previewColors.map((color) {
                final isSelected = _previewColor == color;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _previewColor = color),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? WFColors.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 20),

          // 预览显示区域
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 120),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: WFColors.bgPrimaryColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: WFColors.textLightColor(context).withValues(alpha: 0.3),
              ),
            ),
            child: _previewController.text.isEmpty
                ? Center(
                    child: Text(
                      '请输入预览文本',
                      style: TextStyle(
                        fontSize: 16,
                        color: WFColors.textLightColor(context),
                      ),
                    ),
                  )
                : Text(
                    _previewController.text,
                    style: TextStyle(
                      fontFamily: _fontName,
                      fontSize: 32,
                      height: 1.5,
                      color: _previewColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
          ),
          const SizedBox(height: 12),

          // 提示信息
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: WFColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: WFColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '此处预览使用 Flutter 本地渲染，网页端效果需将字体文件部署后查看。',
                    style: TextStyle(
                      fontSize: 12,
                      color: WFColors.textSecondaryColor(context),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
