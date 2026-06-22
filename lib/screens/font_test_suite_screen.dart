import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../models/project.dart';
import '../services/storage_service.dart';
import '../services/ttf_builder.dart';
import '../theme/app_theme.dart';

/// 字体测试套件
///
/// 用户可以输入自定义文本或选择预设文本，调整字号和字重，
/// 在不同场景（标题、正文、注释、代码）下预览字体效果，
/// 支持亮色/暗色背景切换。
class FontTestSuiteScreen extends StatefulWidget {
  /// 初始字体项目（可选，从首页入口直接传入）
  final FontProject? initialProject;

  const FontTestSuiteScreen({super.key, this.initialProject});

  @override
  State<FontTestSuiteScreen> createState() => _FontTestSuiteScreenState();
}

class _FontTestSuiteScreenState extends State<FontTestSuiteScreen> {
  // ── 字体项目 ──
  List<FontProject> _projects = [];
  FontProject? _selectedProject;

  // ── 测试参数 ──
  String _customText = '';
  double _fontSize = 24.0;
  FontWeight _fontWeight = FontWeight.w400;
  bool _isDarkBackground = false;

  // ── 预设文本 ──
  static const List<Map<String, String>> _presetTexts = [
    {
      'name': '中文段落',
      'text': '天地玄黄，宇宙洪荒。日月盈昃，辰宿列张。寒来暑往，秋收冬藏。闰余成岁，律吕调阳。云腾致雨，露结为霜。金生丽水，玉出昆冈。',
    },
    {
      'name': '英文段落',
      'text': 'The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs. How vexingly quick daft zebras jump!',
    },
    {
      'name': '标点测试',
      'text': '你好！世界？「引号」《书名号》——破折号……省略号、顿号；分号：冒号。句号，逗号',
    },
    {
      'name': '数字测试',
      'text': '0123456789 ①②③④⑤ 一二三四五 壹贰叁肆伍 Ⅰ Ⅱ Ⅲ Ⅳ Ⅴ',
    },
    {
      'name': '常用汉字',
      'text': '的一是不了人我在有他这为之大来以个中上们到说国和地也子时道出会三要于下得可你年生',
    },
    {
      'name': '混合排版',
      'text': 'WriteFont 手迹造字 v2.3 — 让每个人都拥有自己的手写字体！支持中文、English、日本語、한국어。',
    },
  ];

  // ── 预设文本选择 ──
  int _selectedPreset = -1; // -1 表示自定义

  // ── 字体加载状态 ──
  bool _isLoadingFont = false;
  String? _fontFamilyName;

  // ── 字重选项 ──
  static const List<Map<String, dynamic>> _weightOptions = [
    {'label': 'Light', 'weight': FontWeight.w300},
    {'label': 'Regular', 'weight': FontWeight.w400},
    {'label': 'Medium', 'weight': FontWeight.w500},
    {'label': 'Bold', 'weight': FontWeight.w700},
  ];

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
        if (_selectedProject != null) {
          _loadFontForProject(_selectedProject!);
        }
      }
    } catch (e) {
      debugPrint('[FontTestSuite] 加载项目失败: $e');
    }
  }

  /// 为选中的项目加载字体
  Future<void> _loadFontForProject(FontProject project) async {
    setState(() => _isLoadingFont = true);
    try {
      final glyphs = project.glyphs.values.toList();
      if (glyphs.isEmpty) {
        if (mounted) setState(() => _isLoadingFont = false);
        return;
      }

      final builder = TtfBuilder(
        glyphs: glyphs,
        familyName: project.name,
        unitsPerEm: 1000,
        kerningPairs: project.kerningPairs,
        customFamilyName: project.metadata?.familyName ?? project.name,
      );
      final ttfBytes = builder.build();

      // 使用 FontLoader 注册字体供运行时预览
      final familyName = project.metadata?.familyName ?? project.name;
      final fontLoader = FontLoader(familyName);
      fontLoader.addFont(
        Future.value(ByteData.view(ttfBytes.buffer)),
      );
      await fontLoader.load();

      if (mounted) {
        setState(() {
          _fontFamilyName = familyName;
          _isLoadingFont = false;
        });
      }
    } catch (e) {
      debugPrint('[FontTestSuite] 加载字体失败: $e');
      if (mounted) setState(() => _isLoadingFont = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _isDarkBackground ? const Color(0xFF1A1A2E) : Colors.white;
    final textColor = _isDarkBackground ? Colors.white : Colors.black87;

    return Scaffold(
      appBar: WFAppBar(
        title: '字体测试套件',
        actions: [
          // 亮色/暗色切换
          IconButton(
            icon: Icon(_isDarkBackground ? Icons.light_mode : Icons.dark_mode),
            tooltip: _isDarkBackground ? '切换亮色' : '切换暗色',
            onPressed: () => setState(() => _isDarkBackground = !_isDarkBackground),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 控制面板 ──
          _buildControlPanel(),

          // ── 预览区域 ──
          Expanded(
            child: Container(
              color: bgColor,
              child: _isLoadingFont
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: _buildPreviewContent(textColor),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建控制面板
  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: WFColors.textLightColor(context).withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 字体项目选择
          Row(
            children: [
              const Icon(Icons.font_download, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<FontProject>(
                  value: _selectedProject,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(),
                    labelText: '选择字体',
                  ),
                  items: _projects.map((p) {
                    final name = p.metadata?.familyName ?? p.name;
                    return DropdownMenuItem(
                      value: p,
                      child: Text(name, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (project) {
                    if (project != null) {
                      setState(() => _selectedProject = project);
                      _loadFontForProject(project);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 预设文本选择
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _presetTexts.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final isSelected = i == _selectedPreset + 1;
                final label = i == 0 ? '自定义' : _presetTexts[i - 1]['name']!;
                return ChoiceChip(
                  label: Text(label),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() {
                      _selectedPreset = i - 1;
                      if (i > 0) {
                        _customText = _presetTexts[i - 1]['text']!;
                      }
                    });
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // 自定义文本输入（仅自定义模式显示）
          if (_selectedPreset == -1)
            TextField(
              decoration: const InputDecoration(
                hintText: '输入自定义测试文本...',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              onChanged: (v) => setState(() => _customText = v),
            ),
          if (_selectedPreset == -1) const SizedBox(height: 12),

          // 字号滑块
          Row(
            children: [
              const Text('字号', style: TextStyle(fontSize: 13)),
              Expanded(
                child: Slider(
                  value: _fontSize,
                  min: 12,
                  max: 120,
                  divisions: 27,
                  label: '${_fontSize.round()}',
                  onChanged: (v) => setState(() => _fontSize = v),
                ),
              ),
              Text(
                '${_fontSize.round()}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),

          // 字重选择
          Row(
            children: [
              const Text('字重', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 12),
              ...List.generate(_weightOptions.length, (i) {
                final opt = _weightOptions[i];
                final isSelected = _fontWeight == opt['weight'];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(opt['label'] as String),
                    selected: isSelected,
                    onSelected: (_) =>
                        setState(() => _fontWeight = opt['weight'] as FontWeight),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建预览内容
  Widget _buildPreviewContent(Color textColor) {
    final displayText = _selectedPreset >= 0
        ? _presetTexts[_selectedPreset]['text']!
        : _customText;

    if (displayText.isEmpty) {
      return Center(
        child: Text(
          '请输入文本或选择预设文本',
          style: TextStyle(
            color: _isDarkBackground ? Colors.white54 : Colors.black38,
            fontSize: 16,
          ),
        ),
      );
    }

    final fontFamily = _fontFamilyName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 自定义字号预览 ──
        _buildSection(
          '当前预览',
          textColor,
          Text(
            displayText,
            style: TextStyle(
              fontSize: _fontSize,
              fontWeight: _fontWeight,
              fontFamily: fontFamily,
              color: textColor,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── 场景1：标题 ──
        _buildSection(
          '标题场景',
          textColor,
          Text(
            displayText,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              fontFamily: fontFamily,
              color: textColor,
              height: 1.3,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── 场景2：正文 ──
        _buildSection(
          '正文场景',
          textColor,
          Text(
            displayText,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              fontFamily: fontFamily,
              color: textColor,
              height: 1.8,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── 场景3：注释 ──
        _buildSection(
          '注释场景',
          textColor,
          Text(
            displayText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w300,
              fontFamily: fontFamily,
              color: textColor.withValues(alpha: 0.6),
              height: 1.6,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── 场景4：代码 ──
        _buildSection(
          '代码场景',
          textColor,
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isDarkBackground
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isDarkBackground
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.grey.shade300,
              ),
            ),
            child: Text(
              displayText,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                fontFamily: fontFamily ?? 'monospace',
                color: _isDarkBackground
                    ? const Color(0xFF98C379)
                    : const Color(0xFF383A42),
                height: 1.6,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── 多字号阶梯预览 ──
        _buildSection(
          '字号阶梯',
          textColor,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [12, 16, 20, 24, 32, 48, 64].map((size) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${size}px — ${displayText.length > 10 ? displayText.substring(0, 10) : displayText}…',
                  style: TextStyle(
                    fontSize: size.toDouble(),
                    fontWeight: _fontWeight,
                    fontFamily: fontFamily,
                    color: textColor,
                    height: 1.3,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  /// 构建预览区块标题
  Widget _buildSection(String title, Color textColor, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: textColor.withValues(alpha: 0.5),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        content,
      ],
    );
  }
}
