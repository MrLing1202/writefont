import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════
// AI 字体生成器页面
// ═══════════════════════════════════════════════════════════

/// AI智能字体生成器
///
/// 用户通过文字描述自动生成字体风格，支持参数调节、多字号预览、
/// 生成历史记录、一键应用到项目。
class AiFontGeneratorScreen extends StatefulWidget {
  const AiFontGeneratorScreen({super.key});

  @override
  State<AiFontGeneratorScreen> createState() => _AiFontGeneratorScreenState();
}

class _AiFontGeneratorScreenState extends State<AiFontGeneratorScreen> {
  // ── 描述输入 ──
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _previewTextController = TextEditingController(text: '手迹造字');
  int _descCharCount = 0;

  // ── 风格参数 ──
  double _strokeWidth = 5.0;   // 1-10
  double _charWidth = 50.0;    // 0=窄, 50=标准, 100=宽
  double _slantAngle = 0.0;    // -15° ~ 15°
  double _connection = 30.0;   // 0=楷书, 50=行书, 100=草书

  // ── 预览 ──
  double _previewFontSize = 36.0;
  String _generatedFontName = '';
  Map<String, dynamic>? _generatedFontParams;

  // ── 状态 ──
  bool _isGenerating = false;
  bool _isApplying = false;
  double _applyStrength = 80.0;
  double _temperature = 0.7;   // AI 生成温度（0.1~1.0）
  String _lastGenDuration = ''; // 上次生成耗时

  // ── 历史记录 ──
  List<_GenerationRecord> _history = [];

  // ── 预设描述 ──
  static const _presetDescriptions = [
    '优雅的楷书风格，笔画端正，结构匀称',
    '粗犷豪放的毛笔字，苍劲有力',
    '清新秀丽的行楷，流畅自然',
    '古朴典雅的隶书风格，蚕头燕尾',
    '现代简约的印刷体，干净利落',
    '灵动飘逸的行草，笔断意连',
    '端庄大气的颜体，筋骨丰满',
    '瘦劲挺拔的瘦金体，锋芒毕露',
    '圆润可爱的胖胖体，憨态可掬',
  ];

  @override
  void initState() {
    super.initState();
    _descController.addListener(() {
      setState(() => _descCharCount = _descController.text.length);
    });
    _loadHistory();
  }

  @override
  void dispose() {
    _descController.dispose();
    _previewTextController.dispose();
    super.dispose();
  }

  // ── 历史记录持久化 ──

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('ai_font_gen_history');
      if (json != null) {
        final list = jsonDecode(json) as List;
        if (!mounted) return;
        setState(() {
          // 最多加载 20 条历史
          _history = list.take(20).map((e) => _GenerationRecord.fromJson(e)).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_history.map((e) => e.toJson()).toList());
      await prefs.setString('ai_font_gen_history', json);
    } catch (_) {}
  }

  // ── AI 生成 ──

  Future<void> _generate() async {
    final desc = _descController.text.trim();
    if (desc.isEmpty) {
      WFSnackBar.error(context, '请输入字体风格描述');
      return;
    }

    setState(() => _isGenerating = true);
    final stopwatch = Stopwatch()..start();

    try {
      // 读取 API Key
      final prefs = await SharedPreferences.getInstance();
      final apiKey = prefs.getString('glm_api_key') ?? '';

      if (apiKey.isEmpty) {
        if (mounted) {
          setState(() => _isGenerating = false);
          _showApiKeyMissingDialog();
        }
        return;
      }

      // 构造 prompt
      final prompt = _buildPrompt(desc);

      // 带重试的 API 调用（最多重试 2 次）
      Map<String, dynamic>? result;
      for (int attempt = 0; attempt < 3; attempt++) {
        result = await _callGlmApi(apiKey, prompt);
        if (result != null) break;
        if (attempt < 2) {
          debugPrint('AI生成: 第${attempt + 1}次失败，${attempt * 2 + 1}秒后重试');
          await Future.delayed(Duration(seconds: attempt * 2 + 1));
        }
      }

      if (result != null && mounted) {
        stopwatch.stop();
        final duration = stopwatch.elapsedMilliseconds;
        _lastGenDuration = duration < 1000
            ? '${duration}ms'
            : '${(duration / 1000).toStringAsFixed(1)}s';

        setState(() {
          _generatedFontName = result!['fontName'] ?? desc;
          _generatedFontParams = result;
          _isGenerating = false;
        });

        // 保存到历史
        final record = _GenerationRecord(
          description: desc,
          fontName: _generatedFontName,
          params: result,
          strokeWidth: _strokeWidth,
          charWidth: _charWidth,
          slantAngle: _slantAngle,
          connection: _connection,
          createdAt: DateTime.now(),
        );
        _history.insert(0, record);
        if (_history.length > 20) _history = _history.sublist(0, 20);
        await _saveHistory();

        if (mounted) {
          WFSnackBar.success(context, '字体风格生成成功！($_lastGenDuration)');
        }
      } else if (mounted) {
        stopwatch.stop();
        setState(() => _isGenerating = false);
        WFSnackBar.error(context, '生成失败，请重试');
      }
    } catch (e) {
      debugPrint('AI生成失败: $e');
      if (mounted) {
        setState(() => _isGenerating = false);
        WFSnackBar.error(context, '网络错误，请检查网络连接后重试');
      }
    }
  }

  String _buildPrompt(String description) {
    final widthDesc = _charWidth < 33 ? '窄体' : _charWidth > 67 ? '宽体' : '标准';
    final slantDesc = _slantAngle.abs() < 3
        ? '正直'
        : _slantAngle < 0
            ? '左倾${_slantAngle.abs().toStringAsFixed(0)}°'
            : '右倾${_slantAngle.toStringAsFixed(0)}°';
    final connDesc = _connection < 33
        ? '楷书（无连笔）'
        : _connection > 67
            ? '草书（高度连笔）'
            : '行书（适度连笔）';
    final thickDesc = _strokeWidth <= 3
        ? '纤细'
        : _strokeWidth >= 8
            ? '粗壮'
            : '适中';

    return '''你是一个专业的字体设计师。根据以下描述和参数，生成一个详细的字体风格方案。

描述：$description

参数：
- 笔画粗细：${_strokeWidth.toStringAsFixed(0)}（$thickDesc）
- 字形宽度：$widthDesc
- 倾斜角度：$slantDesc
- 连笔程度：$connDesc

请以JSON格式返回：
{
  "fontName": "字体名称",
  "styleDesc": "风格描述",
  "thickness": "笔画特征描述",
  "structure": "结构特征描述",
  "rhythm": "节奏特征描述",
  "mood": "整体气质描述",
  "sampleChars": ["示例字1", "示例字2", "示例字3"]
}

只返回JSON，不要其他文字。字体名称要简洁有特色，不超过6个字。''';
  }

  Future<Map<String, dynamic>?> _callGlmApi(String apiKey, String prompt) async {
    try {
      final uri = Uri.parse('https://open.bigmodel.cn/api/paas/v4/chat/completions');
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'glm-4v-flash',
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'temperature': _temperature,
        }),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices']?[0]?['message']?['content'] as String?;
        if (content != null) {
          // 提取 JSON 部分
          final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
          if (jsonMatch != null) {
            return jsonDecode(jsonMatch.group(0)!);
          }
        }
      }
    } on TimeoutException {
      debugPrint('API请求超时');
    } catch (e) {
      debugPrint('API调用失败: $e');
    }
    return null;
  }

  void _showApiKeyMissingDialog() {
    WFDialog.show(
      context,
      title: '需要配置 API Key',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.vpn_key, size: 48, color: WFColors.warning),
          const SizedBox(height: 16),
          Text(
            '请先在设置中配置智谱AI的API Key才能使用AI生成功能。\n\n'
            'API Key 可在 https://open.bigmodel.cn 免费获取。',
            style: TextStyle(fontSize: 14, color: WFColors.textSecondaryColor(context), height: 1.5),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('稍后再说'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, '/settings');
          },
          child: const Text('去设置'),
        ),
      ],
    );
  }

  // ── 应用到项目 ──

  Future<void> _applyToProject() async {
    if (_generatedFontParams == null) {
      WFSnackBar.show(context, '请先生成字体风格');
      return;
    }

    // 这里可以跳转到项目选择页面，或者直接保存配置
    // 简化实现：保存生成参数供其他模块使用
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ai_font_last_params', jsonEncode({
        'params': _generatedFontParams,
        'strength': _applyStrength / 100.0,
        'strokeWidth': _strokeWidth,
        'charWidth': _charWidth,
        'slantAngle': _slantAngle,
        'connection': _connection,
        'appliedAt': DateTime.now().toIso8601String(),
      }));

      if (mounted) {
        WFSnackBar.success(context, '字体风格已保存，可在风格迁移中使用');
      }
    } catch (e) {
      debugPrint('保存失败: $e');
      if (mounted) {
        WFSnackBar.error(context, '保存失败，请重试');
      }
    }
  }

  // ── UI 构建 ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WFAppBar(
        title: 'AI 智能字体生成',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 描述输入区 ──
                WFAnimations.fadeInSlide(_buildDescriptionSection()),
                const SizedBox(height: 16),

                // ── 参数调节区 ──
                WFAnimations.fadeInSlide(
                  _buildParameterSection(),
                  delay: const Duration(milliseconds: 80),
                ),
                const SizedBox(height: 16),

                // ── 预览区 ──
                WFAnimations.fadeInSlide(
                  _buildPreviewSection(),
                  delay: const Duration(milliseconds: 160),
                ),
                const SizedBox(height: 16),

                // ── 应用设置 ──
                if (_generatedFontParams != null)
                  WFAnimations.fadeInSlide(
                    _buildApplySection(),
                    delay: const Duration(milliseconds: 200),
                  ),
                if (_generatedFontParams != null) const SizedBox(height: 16),

                // ── 生成历史 ──
                if (_history.isNotEmpty)
                  WFAnimations.fadeInSlide(
                    _buildHistorySection(),
                    delay: const Duration(milliseconds: 240),
                  ),
                if (_history.isNotEmpty) const SizedBox(height: 24),

                // ── 底部操作栏 ──
                _buildBottomActions(),
                const SizedBox(height: 32),
              ],
            ),
          ),

          // ── 全局加载遮罩 ──
          if (_isGenerating)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: Center(
                child: WFCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: WFColors.primary),
                      const SizedBox(height: 16),
                      Text(
                        'AI 正在生成字体风格...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: WFColors.textPrimaryColor(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '请稍候，正在分析您的描述',
                        style: TextStyle(fontSize: 13, color: WFColors.textSecondaryColor(context)),
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

  // ── 描述输入区域 ──

  Widget _buildDescriptionSection() {
    return WFCard(
      accentColor: WFColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: WFColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.edit_note, size: 22, color: WFColors.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '字体风格描述',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: WFColors.textPrimaryColor(context),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '描述你想要的字体风格，越详细效果越好',
                      style: TextStyle(fontSize: 13, color: WFColors.textSecondaryColor(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 文本输入框
          TextField(
            controller: _descController,
            maxLines: 4,
            maxLength: 200,
            decoration: InputDecoration(
              hintText: '例如：优雅的楷书风格，笔画端正，结构匀称...',
              hintStyle: TextStyle(color: WFColors.textLightColor(context)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: WFColors.textLightColor(context)),
              ),
              contentPadding: const EdgeInsets.all(14),
              counterText: '$_descCharCount/200',
              counterStyle: TextStyle(
                color: _descCharCount > 180 ? WFColors.warning : WFColors.textLightColor(context),
                fontSize: 12,
              ),
            ),
            style: TextStyle(fontSize: 15, color: WFColors.textPrimaryColor(context), height: 1.5),
          ),
          const SizedBox(height: 12),

          // 示例按钮
          Text(
            '快速选择示例：',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: WFColors.textSecondaryColor(context)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presetDescriptions.map((desc) {
              return ActionChip(
                label: Text(
                  desc,
                  style: const TextStyle(fontSize: 12, color: WFColors.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                backgroundColor: WFColors.primary.withValues(alpha: 0.08),
                side: BorderSide(color: WFColors.primary.withValues(alpha: 0.2)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                onPressed: () => _descController.text = desc,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── 参数调节区域 ──

  Widget _buildParameterSection() {
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
                child: const Icon(Icons.tune, size: 22, color: WFColors.info),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '风格参数调节',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: WFColors.textPrimaryColor(context),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '精细控制字体的各个特征',
                      style: TextStyle(fontSize: 13, color: WFColors.textSecondaryColor(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 笔画粗细
          _buildSliderRow(
            icon: Icons.line_weight,
            label: '笔画粗细',
            value: _strokeWidth,
            min: 1,
            max: 10,
            divisions: 9,
            valueLabel: _strokeWidth.toStringAsFixed(0),
            onChanged: (v) => setState(() => _strokeWidth = v),
          ),
          const SizedBox(height: 12),

          // 字形宽度
          _buildSliderRow(
            icon: Icons.swap_horiz,
            label: '字形宽度',
            value: _charWidth,
            min: 0,
            max: 100,
            divisions: 100,
            valueLabel: _charWidth < 33 ? '窄' : _charWidth > 67 ? '宽' : '标准',
            onChanged: (v) => setState(() => _charWidth = v),
          ),
          const SizedBox(height: 12),

          // 倾斜角度
          _buildSliderRow(
            icon: Icons.format_italic,
            label: '倾斜角度',
            value: _slantAngle,
            min: -15,
            max: 15,
            divisions: 30,
            valueLabel: '${_slantAngle.toStringAsFixed(0)}°',
            onChanged: (v) => setState(() => _slantAngle = v),
          ),
          const SizedBox(height: 12),

          // 连笔程度
          _buildSliderRow(
            icon: Icons.gesture,
            label: '连笔程度',
            value: _connection,
            min: 0,
            max: 100,
            divisions: 100,
            valueLabel: _connection < 33 ? '楷书' : _connection > 67 ? '草书' : '行书',
            onChanged: (v) => setState(() => _connection = v),
          ),
          const SizedBox(height: 12),

          // 创意温度
          _buildSliderRow(
            icon: Icons.local_fire_department,
            label: '创意度',
            value: _temperature,
            min: 0.1,
            max: 1.0,
            divisions: 9,
            valueLabel: _temperature <= 0.3 ? '保守' : _temperature >= 0.8 ? '大胆' : '平衡',
            onChanged: (v) => setState(() => _temperature = v),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required IconData icon,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String valueLabel,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: WFColors.info),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: WFColors.textPrimaryColor(context)),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: WFColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                valueLabel,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: WFColors.info),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: WFColors.info,
            inactiveTrackColor: WFColors.info.withValues(alpha: 0.15),
            thumbColor: WFColors.info,
            overlayColor: WFColors.info.withValues(alpha: 0.1),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  // ── 预览区域 ──

  Widget _buildPreviewSection() {
    return WFCard(
      accentColor: WFColors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: WFColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.preview, size: 22, color: WFColors.success),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '生成预览',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: WFColors.textPrimaryColor(context),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '查看字体效果，支持多字号预览',
                      style: TextStyle(fontSize: 13, color: WFColors.textSecondaryColor(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 自定义预览文本
          TextField(
            controller: _previewTextController,
            decoration: InputDecoration(
              hintText: '输入预览文本',
              prefixIcon: const Icon(Icons.text_fields, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),

          // 字号切换
          Row(
            children: [
              Text('字号:', style: TextStyle(fontSize: 13, color: WFColors.textSecondaryColor(context))),
              const SizedBox(width: 8),
              ...([12.0, 24.0, 36.0, 48.0].map((size) {
                final isSelected = _previewFontSize == size;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${size.toInt()}px', style: TextStyle(fontSize: 12)),
                    selected: isSelected,
                    selectedColor: WFColors.success.withValues(alpha: 0.15),
                    labelStyle: TextStyle(
                      color: isSelected ? WFColors.success : WFColors.textSecondaryColor(context),
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: isSelected ? WFColors.success : WFColors.textLightColor(context),
                    ),
                    onSelected: (_) => setState(() => _previewFontSize = size),
                  ),
                );
              })),
            ],
          ),
          const SizedBox(height: 16),

          // 预览区域
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: WFColors.bgPrimaryColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: WFColors.textLightColor(context).withValues(alpha: 0.5)),
            ),
            child: _generatedFontParams != null
                ? _buildPreviewContent()
                : _buildEmptyPreview(),
          ),

          // 风格特征标签
          if (_generatedFontParams != null) ...[
            const SizedBox(height: 12),
            _buildStyleTags(),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyPreview() {
    return Column(
      children: [
        Icon(
          Icons.font_download_outlined,
          size: 48,
          color: WFColors.textLightColor(context).withValues(alpha: 0.5),
        ),
        const SizedBox(height: 12),
        Text(
          '输入描述后点击"生成"',
          style: TextStyle(fontSize: 14, color: WFColors.textLightColor(context)),
        ),
        const SizedBox(height: 4),
        Text(
          'AI 将为您生成独特的字体风格',
          style: TextStyle(fontSize: 12, color: WFColors.textLightColor(context)),
        ),
      ],
    );
  }

  Widget _buildPreviewContent() {
    final previewText = _previewTextController.text.isNotEmpty
        ? _previewTextController.text
        : '手迹造字';
    final params = _generatedFontParams!;

    // 根据生成参数调整预览样式
    final fontWeight = _strokeWidth > 6 ? FontWeight.bold : FontWeight.normal;
    final letterSpacing = _charWidth > 67 ? 4.0 : _charWidth < 33 ? -1.0 : 1.0;

    return Column(
      children: [
        // 字体名称
        if (params['fontName'] != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: WFColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              params['fontName'],
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: WFColors.success,
              ),
            ),
          ),
        const SizedBox(height: 16),

        // 预览文字
        Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001) // perspective
            ..rotateZ(_slantAngle * 3.14159 / 180),
          child: Text(
            previewText,
            style: TextStyle(
              fontSize: _previewFontSize,
              fontWeight: fontWeight,
              letterSpacing: letterSpacing,
              color: WFColors.textPrimaryColor(context),
              height: 1.3,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 12),

        // 样例字符
        if (params['sampleChars'] != null)
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: (params['sampleChars'] as List).map((char) {
              return Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: WFColors.bgCardColor(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: WFColors.textLightColor(context).withValues(alpha: 0.3)),
                ),
                child: Center(
                  child: Text(
                    char.toString(),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: fontWeight,
                      letterSpacing: letterSpacing,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildStyleTags() {
    final params = _generatedFontParams!;
    final tags = <String, Color>{};

    if (params['thickness'] != null) {
      tags[params['thickness']] = WFColors.primary;
    }
    if (params['structure'] != null) {
      tags[params['structure']] = WFColors.info;
    }
    if (params['rhythm'] != null) {
      tags[params['rhythm']] = WFColors.warning;
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: tags.entries.map((entry) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: entry.value.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: entry.value.withValues(alpha: 0.2)),
          ),
          child: Text(
            entry.key,
            style: TextStyle(fontSize: 11, color: entry.value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
    );
  }

  // ── 应用设置区 ──

  Widget _buildApplySection() {
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
                child: const Icon(Icons.auto_fix_high, size: 22, color: WFColors.warning),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '应用设置',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: WFColors.textPrimaryColor(context),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '调整应用强度并保存到项目',
                      style: TextStyle(fontSize: 13, color: WFColors.textSecondaryColor(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 强度滑块
          Row(
            children: [
              const Icon(Icons.opacity, size: 18, color: WFColors.warning),
              const SizedBox(width: 8),
              Text(
                '应用强度',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: WFColors.textPrimaryColor(context)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: WFColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_applyStrength.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: WFColors.warning,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: WFColors.warning,
              inactiveTrackColor: WFColors.warning.withValues(alpha: 0.15),
              thumbColor: WFColors.warning,
              overlayColor: WFColors.warning.withValues(alpha: 0.1),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: _applyStrength,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: (v) => setState(() => _applyStrength = v),
            ),
          ),
        ],
      ),
    );
  }

  // ── 历史记录区 ──

  Widget _buildHistorySection() {
    return WFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 20, color: WFColors.textSecondaryColor(context)),
              const SizedBox(width: 8),
              Text(
                '生成历史',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textPrimaryColor(context),
                ),
              ),
              const Spacer(),
              Text(
                '${_history.length}/20',
                style: TextStyle(fontSize: 12, color: WFColors.textLightColor(context)),
              ),
              if (_history.isNotEmpty) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _clearAllHistory,
                  child: Text(
                    '清空',
                    style: TextStyle(fontSize: 12, color: WFColors.warning),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          ...List.generate(_history.length, (index) {
            final record = _history[index];
            return _buildHistoryItem(record, index);
          }),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(_GenerationRecord record, int index) {
    final timeAgo = _formatTimeAgo(record.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: WFColors.bgPrimaryColor(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: WFColors.textLightColor(context).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.fontName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: WFColors.textPrimaryColor(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  record.description,
                  style: TextStyle(fontSize: 12, color: WFColors.textSecondaryColor(context)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  timeAgo,
                  style: TextStyle(fontSize: 11, color: WFColors.textLightColor(context)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.replay, size: 20, color: WFColors.info),
            tooltip: '应用此记录',
            onPressed: () => _applyHistory(record),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 20, color: WFColors.textLightColor(context)),
            tooltip: '删除',
            onPressed: () => _deleteHistory(index),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${time.month}/${time.day}';
  }

  void _applyHistory(_GenerationRecord record) {
    setState(() {
      _descController.text = record.description;
      _strokeWidth = record.strokeWidth;
      _charWidth = record.charWidth;
      _slantAngle = record.slantAngle;
      _connection = record.connection;
      _generatedFontName = record.fontName;
      _generatedFontParams = record.params;
    });
    WFSnackBar.show(context, '已加载历史记录');
  }

  Future<void> _deleteHistory(int index) async {
    setState(() => _history.removeAt(index));
    await _saveHistory();
    WFSnackBar.show(context, '已删除');
  }

  Future<void> _clearAllHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史'),
        content: const Text('确定清空所有生成历史记录？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('清空', style: TextStyle(color: WFColors.warning)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _history.clear());
      await _saveHistory();
      WFSnackBar.show(context, '历史记录已清空');
    }
  }

  // ── 底部操作栏 ──

  Widget _buildBottomActions() {
    return Row(
      children: [
        // 生成按钮
        Expanded(
          child: WFPrimaryButton(
            text: _isGenerating ? '生成中...' : '✨ 开始生成',
            icon: _isGenerating ? null : Icons.auto_awesome,
            onPressed: _isGenerating ? null : _generate,
          ),
        ),
        const SizedBox(width: 12),

        // 应用按钮
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _generatedFontParams != null ? _applyToProject : null,
              icon: const Icon(Icons.check_circle_outline, size: 20),
              label: const Text('应用到项目'),
              style: OutlinedButton.styleFrom(
                foregroundColor: WFColors.success,
                side: BorderSide(
                  color: _generatedFontParams != null
                      ? WFColors.success
                      : WFColors.textLightColor(context),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// 生成记录数据模型
// ═══════════════════════════════════════════════════════════

class _GenerationRecord {
  final String description;
  final String fontName;
  final Map<String, dynamic> params;
  final double strokeWidth;
  final double charWidth;
  final double slantAngle;
  final double connection;
  final DateTime createdAt;

  _GenerationRecord({
    required this.description,
    required this.fontName,
    required this.params,
    required this.strokeWidth,
    required this.charWidth,
    required this.slantAngle,
    required this.connection,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'description': description,
        'fontName': fontName,
        'params': params,
        'strokeWidth': strokeWidth,
        'charWidth': charWidth,
        'slantAngle': slantAngle,
        'connection': connection,
        'createdAt': createdAt.toIso8601String(),
      };

  factory _GenerationRecord.fromJson(Map<String, dynamic> json) => _GenerationRecord(
        description: json['description'] ?? '',
        fontName: json['fontName'] ?? '',
        params: Map<String, dynamic>.from(json['params'] ?? {}),
        strokeWidth: (json['strokeWidth'] ?? 5).toDouble(),
        charWidth: (json['charWidth'] ?? 50).toDouble(),
        slantAngle: (json['slantAngle'] ?? 0).toDouble(),
        connection: (json['connection'] ?? 30).toDouble(),
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      );
}
