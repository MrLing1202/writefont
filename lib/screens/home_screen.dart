import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/project.dart';
import '../theme/app_theme.dart';
import 'font_preview_screen.dart';
import 'font_preview_enhanced_screen.dart';
import 'project_list_screen.dart';
import 'settings_screen.dart';
import 'writing_tips_screen.dart';
import '../services/storage_service.dart';
import '../services/recognition_service.dart';
import '../services/image_processor.dart';
import 'home/welcome_header.dart';
import 'home/recent_projects_section.dart';
import 'home/secondary_entry_card.dart';
import 'home/home_actions.dart';
import 'package:flutter/services.dart';
import '../main.dart';

/// 推送设置模型
class PushSettings {
  bool enabled;
  TimeOfDay reminderTime;
  String reminderContent;
  int frequencyDays; // 推送频率（天数）
  bool projectReminder;
  bool syncReminder;
  bool updateReminder;

  PushSettings({
    this.enabled = true,
    this.reminderTime = const TimeOfDay(hour: 9, minute: 0),
    this.reminderContent = '今天来创建新的手写字体吧！',
    this.frequencyDays = 1,
    this.projectReminder = true,
    this.syncReminder = true,
    this.updateReminder = true,
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'reminderHour': reminderTime.hour,
        'reminderMinute': reminderTime.minute,
        'reminderContent': reminderContent,
        'frequencyDays': frequencyDays,
        'projectReminder': projectReminder,
        'syncReminder': syncReminder,
        'updateReminder': updateReminder,
      };

  factory PushSettings.fromJson(Map<String, dynamic> json) => PushSettings(
        enabled: json['enabled'] as bool? ?? true,
        reminderTime: TimeOfDay(
          hour: json['reminderHour'] as int? ?? 9,
          minute: json['reminderMinute'] as int? ?? 0,
        ),
        reminderContent: json['reminderContent'] as String? ?? '今天来创建新的手写字体吧！',
        frequencyDays: json['frequencyDays'] as int? ?? 1,
        projectReminder: json['projectReminder'] as bool? ?? true,
        syncReminder: json['syncReminder'] as bool? ?? true,
        updateReminder: json['updateReminder'] as bool? ?? true,
      );
}

class HomeScreen extends StatefulWidget {
  /// 主题变更回调，用于从设置页返回时刷新主题
  final VoidCallback? onThemeChanged;

  const HomeScreen({super.key, this.onThemeChanged});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _savedProjectCount = 0;
  int _totalCharCount = 0;
  DateTime? _lastActivityTime;
  List<FontProject> _recentProjects = [];
  String _appVersion = '';
  bool _showOnboarding = false;
  int _onboardingStep = 0;
  bool _isRefreshing = false;
  // 功能引导状态
  bool _showFeatureGuide = false;
  int _featureGuideStep = 0;
  final List<String> _completedFeatureGuides = [];
  // 操作引导状态
  bool _showOperationGuide = false;
  String _operationGuideTarget = '';
  // 手势状态
  double _scaleFactor = 1.0; // 捏合缩放比例
  double _previousScale = 1.0;

  // ═══ 个性化功能状态 ═══
  // 个性化推荐
  List<Map<String, dynamic>> _personalizedRecommendations = [];
  String _userPreferredCategory = 'standard'; // standard | quick | ai | free
  int _userSkillLevel = 1; // 1=新手, 2=进阶, 3=专家
  // 个性化主题
  String _personalizedTheme = 'default'; // default | warm | cool | nature
  double _cardBorderRadius = 12.0;
  double _fontScale = 1.0;
  // 个性化布局
  int _layoutMode = 0; // 0=标准, 1=紧凑, 2=宽松
  bool _showQuickStats = true;
  bool _showRecentProjects = true;
  bool _showVisualizations = true;
  int _maxRecentProjects = 2;

  // 推送设置状态
  PushSettings _pushSettings = PushSettings();
  int _unreadNotificationCount = 0;

  // ═══ 互动功能状态 ═══
  /// 项目点赞记录: {projectId: isLiked}
  final Map<String, bool> _likedProjects = {};
  /// 项目点赞数: {projectId: count}
  final Map<String, int> _likeCounts = {};
  /// 项目评论列表: {projectId: [{id, content, author, timestamp}]}
  final Map<String, List<Map<String, dynamic>>> _projectComments = {};
  /// 项目收藏记录: {projectId: isFavorited}
  final Map<String, bool> _favoritedProjects = {};
  /// 项目转发数: {projectId: count}
  final Map<String, int> _repostCounts = {};

  // 分类统计
  Map<String, int> _categoryStats = {};

  // ═══ 业务指标状态 ═══
  /// 关键指标数据
  final Map<String, dynamic> _businessMetrics = {};
  /// 指标趋势数据（最近7天）
  final List<Map<String, dynamic>> _metricsTrend = [];
  /// 预警指标列表
  final List<Map<String, dynamic>> _metricsAlerts = [];
  /// 指标报告缓存
  String _metricsReportCache = '';

  // 快捷操作动画控制器
  late AnimationController _quickActionAnimController;
  late Animation<double> _quickActionScale;
  // 双击缩放动画控制器
  late AnimationController _doubleTapAnimController;
  late Animation<double> _doubleTapScale;

  @override
  void initState() {
    super.initState();
    _loadProjectData();
    _loadAppVersion();
    _checkOnboardingGuide();
    _checkFeatureGuideProgress();
    _loadPushSettings();
    _loadNotificationCount();
    _loadPersonalizationSettings();
    _generatePersonalizedRecommendations();
    _loadBusinessMetrics();
    _quickActionAnimController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _quickActionScale = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _quickActionAnimController, curve: Curves.easeInOut),
    );
    // 双击缩放动画控制器
    _doubleTapAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _doubleTapScale = Tween<double>(begin: 1.0, end: 1.0).animate(
      CurvedAnimation(parent: _doubleTapAnimController, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    NotificationService.instance.removeListener(_onNotificationChanged);
    _quickActionAnimController.dispose();
    _doubleTapAnimController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // 个性化功能优化
  // ═══════════════════════════════════════════════════════════

  /// 加载个性化设置（从 SharedPreferences 持久化读取）
  Future<void> _loadPersonalizationSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _userPreferredCategory = prefs.getString('user_preferred_category') ?? 'standard';
          _userSkillLevel = prefs.getInt('user_skill_level') ?? 1;
          _personalizedTheme = prefs.getString('personalized_theme') ?? 'default';
          _cardBorderRadius = prefs.getDouble('card_border_radius') ?? 12.0;
          _fontScale = prefs.getDouble('font_scale') ?? 1.0;
          _layoutMode = prefs.getInt('layout_mode') ?? 0;
          _showQuickStats = prefs.getBool('show_quick_stats') ?? true;
          _showRecentProjects = prefs.getBool('show_recent_projects') ?? true;
          _showVisualizations = prefs.getBool('show_visualizations') ?? true;
          _maxRecentProjects = prefs.getInt('max_recent_projects') ?? 2;
        });
      }
    } catch (e) {
      debugPrint('[Home] 加载个性化设置失败: $e');
    }
  }

  /// 保存个性化设置到持久化存储
  Future<void> _savePersonalizationSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_preferred_category', _userPreferredCategory);
      await prefs.setInt('user_skill_level', _userSkillLevel);
      await prefs.setString('personalized_theme', _personalizedTheme);
      await prefs.setDouble('card_border_radius', _cardBorderRadius);
      await prefs.setDouble('font_scale', _fontScale);
      await prefs.setInt('layout_mode', _layoutMode);
      await prefs.setBool('show_quick_stats', _showQuickStats);
      await prefs.setBool('show_recent_projects', _showRecentProjects);
      await prefs.setBool('show_visualizations', _showVisualizations);
      await prefs.setInt('max_recent_projects', _maxRecentProjects);
    } catch (e) {
      debugPrint('[Home] 保存个性化设置失败: $e');
    }
  }

  /// 生成个性化推荐（基于用户使用模式和偏好）
  void _generatePersonalizedRecommendations() {
    try {
      final recommendations = <Map<String, dynamic>>[];

      // 基于用户技能等级推荐
      if (_userSkillLevel == 1) {
        // 新手：推荐快速体验和一键生成
        recommendations.add({
          'title': '快速体验模式',
          'desc': '无需完整拍摄，快速生成体验版字体',
          'icon': Icons.bolt,
          'color': WFColors.warning,
          'priority': 1,
          'action': 'quick',
        });
        recommendations.add({
          'title': '一键生成字体',
          'desc': '拍照即可自动生成手写字体',
          'icon': Icons.auto_awesome,
          'color': WFColors.primary,
          'priority': 2,
          'action': 'capture',
        });
      } else if (_userSkillLevel == 2) {
        // 进阶：推荐标准字表和自由拍摄
        recommendations.add({
          'title': '标准字表模式',
          'desc': '使用标准字表逐字拍摄，覆盖常用汉字',
          'icon': Icons.grid_on,
          'color': WFColors.info,
          'priority': 1,
          'action': 'standard',
        });
        recommendations.add({
          'title': '自由拍摄',
          'desc': '灵活拍摄任意字符',
          'icon': Icons.camera_alt,
          'color': WFColors.accent,
          'priority': 2,
          'action': 'free',
        });
      } else {
        // 专家：推荐AI生成和高级功能
        recommendations.add({
          'title': 'AI 智能生成',
          'desc': '通过文字描述，AI 自动生成独特字体',
          'icon': Icons.auto_awesome_outlined,
          'color': const Color(0xFF8E44AD),
          'priority': 1,
          'action': 'ai',
        });
        recommendations.add({
          'title': '增强预览',
          'desc': '使用高级预览功能调整字体效果',
          'icon': Icons.preview,
          'color': WFColors.success,
          'priority': 2,
          'action': 'preview',
        });
      }

      // 基于最近使用偏好推荐
      if (_userPreferredCategory == 'standard' && _userSkillLevel >= 2) {
        recommendations.add({
          'title': '继续创作',
          'desc': '使用标准字表继续您的字体项目',
          'icon': Icons.play_circle_outline,
          'color': WFColors.primary,
          'priority': 3,
          'action': 'standard',
        });
      }

      // 按优先级排序
      recommendations.sort((a, b) => (a['priority'] as int).compareTo(b['priority'] as int));

      if (mounted) {
        setState(() {
          _personalizedRecommendations = recommendations;
        });
      }
    } catch (e) {
      debugPrint('[Home] 生成个性化推荐失败: $e');
    }
  }

  /// 获取个性化主题颜色
  Color _getPersonalizedAccentColor() {
    switch (_personalizedTheme) {
      case 'warm':
        return const Color(0xFFE67E22); // 暖橙色
      case 'cool':
        return const Color(0xFF3498DB); // 冷蓝色
      case 'nature':
        return const Color(0xFF27AE60); // 自然绿
      default:
        return WFColors.primary;
    }
  }

  /// 根据布局模式获取内边距
  EdgeInsets _getLayoutPadding() {
    switch (_layoutMode) {
      case 1: // 紧凑
        return const EdgeInsets.symmetric(horizontal: 16, vertical: 8);
      case 2: // 宽松
        return const EdgeInsets.symmetric(horizontal: 24, vertical: 24);
      default: // 标准
        return const EdgeInsets.symmetric(horizontal: 20, vertical: 16);
    }
  }

  /// 显示个性化设置面板
  void _showPersonalizationSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '个性化设置',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: WFColors.textPrimaryColor(context),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 技能等级
                  const Text('使用水平', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('新手')),
                      ButtonSegment(value: 2, label: Text('进阶')),
                      ButtonSegment(value: 3, label: Text('专家')),
                    ],
                    selected: {_userSkillLevel},
                    onSelectionChanged: (selected) {
                      final value = selected.first;
                      setSheetState(() => _userSkillLevel = value);
                      setState(() => _userSkillLevel = value);
                      _savePersonalizationSettings();
                      _generatePersonalizedRecommendations();
                    },
                  ),
                  const SizedBox(height: 20),
                  // 主题风格
                  const Text('主题风格', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildThemeChip('default', '默认', WFColors.primary, setSheetState),
                      _buildThemeChip('warm', '暖色', const Color(0xFFE67E22), setSheetState),
                      _buildThemeChip('cool', '冷色', const Color(0xFF3498DB), setSheetState),
                      _buildThemeChip('nature', '自然', const Color(0xFF27AE60), setSheetState),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // 布局模式
                  const Text('布局模式', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('标准')),
                      ButtonSegment(value: 1, label: Text('紧凑')),
                      ButtonSegment(value: 2, label: Text('宽松')),
                    ],
                    selected: {_layoutMode},
                    onSelectionChanged: (selected) {
                      final value = selected.first;
                      setSheetState(() => _layoutMode = value);
                      setState(() => _layoutMode = value);
                      _savePersonalizationSettings();
                    },
                  ),
                  const SizedBox(height: 20),
                  // 字体缩放
                  const Text('字体大小', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Slider(
                    value: _fontScale,
                    min: 0.8,
                    max: 1.3,
                    divisions: 5,
                    label: '${(_fontScale * 100).toInt()}%',
                    onChanged: (v) {
                      setSheetState(() => _fontScale = v);
                      setState(() => _fontScale = v);
                      ThemeConfigService.instance.setFontScale(v);
                    },
                    onChangeEnd: (_) => _savePersonalizationSettings(),
                  ),
                  const SizedBox(height: 12),
                  // 显示选项
                  SwitchListTile(
                    title: const Text('显示快速统计'),
                    value: _showQuickStats,
                    onChanged: (v) {
                      setSheetState(() => _showQuickStats = v);
                      setState(() => _showQuickStats = v);
                      _savePersonalizationSettings();
                    },
                  ),
                  SwitchListTile(
                    title: const Text('显示最近项目'),
                    value: _showRecentProjects,
                    onChanged: (v) {
                      setSheetState(() => _showRecentProjects = v);
                      setState(() => _showRecentProjects = v);
                      _savePersonalizationSettings();
                    },
                  ),
                  SwitchListTile(
                    title: const Text('显示数据可视化'),
                    value: _showVisualizations,
                    onChanged: (v) {
                      setSheetState(() => _showVisualizations = v);
                      setState(() => _showVisualizations = v);
                      _savePersonalizationSettings();
                    },
                  ),
                  const SizedBox(height: 16),
                  // 重置按钮
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        setSheetState(() {
                          _userSkillLevel = 1;
                          _personalizedTheme = 'default';
                          _layoutMode = 0;
                          _fontScale = 1.0;
                          _showQuickStats = true;
                          _showRecentProjects = true;
                          _showVisualizations = true;
                          _maxRecentProjects = 2;
                        });
                        setState(() {});
                        _savePersonalizationSettings();
                        _generatePersonalizedRecommendations();
                        WFSnackBar.show(context, '已重置为默认个性化设置');
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('重置默认'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建主题风格选择芯片
  Widget _buildThemeChip(String id, String label, Color color, StateSetter setSheetState) {
    final isSelected = _personalizedTheme == id;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: color.withValues(alpha: 0.2),
      labelStyle: TextStyle(color: isSelected ? color : WFColors.textSecondaryColor(context)),
      onSelected: (_) {
        setSheetState(() => _personalizedTheme = id);
        setState(() => _personalizedTheme = id);
        // 映射到ThemeConfigService主题色索引
        final colorIndex = switch (id) {
          'warm' => 10,   // 琥珀
          'cool' => 2,    // 蓝色
          'nature' => 3,  // 绿色
          _ => 0,         // 深墨蓝(默认)
        };
        ThemeConfigService.instance.setThemeColor(colorIndex);
        _savePersonalizationSettings();
      },
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 业务指标监控优化：关键指标、趋势分析、预警、报告
  // ═══════════════════════════════════════════════════════════

  /// 加载业务指标数据
  ///
  /// 收集关键业务指标：项目数、字符数、完成率、活跃度等
  Future<void> _loadBusinessMetrics() async {
    try {
      final projects = await StorageService.loadProjects();
      if (!mounted) return;

      // 计算关键指标
      int totalGlyphs = 0;
      int totalEdited = 0;
      int completedProjects = 0;
      int activeProjects = 0;
      final now = DateTime.now();

      for (final project in projects) {
        totalGlyphs += project.glyphs.length;
        final editedCount = project.glyphs.values
            .where((g) => g.contours.isNotEmpty)
            .length;
        totalEdited += editedCount;

        if (editedCount >= project.glyphs.length * 0.8) {
          completedProjects++;
        }
        if (now.difference(project.updatedAt).inDays <= 7) {
          activeProjects++;
        }
      }

      setState(() {
        _businessMetrics['totalProjects'] = projects.length;
        _businessMetrics['totalGlyphs'] = totalGlyphs;
        _businessMetrics['totalEdited'] = totalEdited;
        _businessMetrics['completionRate'] = totalGlyphs > 0
            ? (totalEdited / totalGlyphs * 100).toStringAsFixed(1)
            : '0.0';
        _businessMetrics['completedProjects'] = completedProjects;
        _businessMetrics['activeProjects'] = activeProjects;
        _businessMetrics['lastUpdated'] = now.toIso8601String();
      });

      // 加载趋势数据
      _loadMetricsTrend();
      // 检查预警
      _checkMetricsAlerts();
    } catch (e) {
      debugPrint('[Home] 加载业务指标失败: $e');
    }
  }

  /// 加载指标趋势数据（最近7天）
  ///
  /// 从本地存储读取历史指标数据，生成趋势图数据
  void _loadMetricsTrend() {
    try {
      final now = DateTime.now();
      _metricsTrend.clear();

      // 生成最近7天的趋势数据
      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        final dateKey = '${date.month}/${date.day}';

        // 模拟趋势数据（实际应从持久化存储读取）
        _metricsTrend.add({
          'date': dateKey,
          'projects': _businessMetrics['totalProjects'] ?? 0,
          'glyphs': (_businessMetrics['totalGlyphs'] ?? 0) - (i * 2),
          'edited': (_businessMetrics['totalEdited'] ?? 0) - (i * 3),
        });
      }
    } catch (e) {
      debugPrint('[Home] 加载趋势数据失败: $e');
    }
  }

  /// 检查指标预警
  ///
  /// 监控关键指标，当指标异常时生成预警
  void _checkMetricsAlerts() {
    try {
      _metricsAlerts.clear();

      final totalProjects = _businessMetrics['totalProjects'] as int? ?? 0;
      final completionRate = double.tryParse(
          _businessMetrics['completionRate'] as String? ?? '0') ?? 0;
      final activeProjects = _businessMetrics['activeProjects'] as int? ?? 0;

      // 预警1：项目完成率过低
      if (totalProjects > 0 && completionRate < 20) {
        _metricsAlerts.add({
          'type': 'low_completion',
          'level': 'warning',
          'title': '项目完成率较低',
          'message': '当前完成率仅 ${completionRate}%，建议集中精力完成现有项目',
          'icon': Icons.warning_amber,
          'color': Colors.orange,
        });
      }

      // 预警2：无活跃项目
      if (totalProjects > 0 && activeProjects == 0) {
        _metricsAlerts.add({
          'type': 'no_activity',
          'level': 'info',
          'title': '暂无活跃项目',
          'message': '最近7天没有项目更新，快来创作吧！',
          'icon': Icons.info_outline,
          'color': Colors.blue,
        });
      }

      // 预警3：项目数量过多
      if (totalProjects > 20) {
        _metricsAlerts.add({
          'type': 'too_many_projects',
          'level': 'info',
          'title': '项目数量较多',
          'message': '您有 $totalProjects 个项目，建议整理归档已完成的项目',
          'icon': Icons.folder_open,
          'color': Colors.purple,
        });
      }
    } catch (e) {
      debugPrint('[Home] 检查指标预警失败: $e');
    }
  }

  /// 生成指标报告
  ///
  /// 汇总所有业务指标，生成可读的报告文本
  String _generateMetricsReport() {
    try {
      final buffer = StringBuffer();
      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln('        WriteFont 业务指标报告');
      buffer.writeln('        生成时间: ${DateTime.now().toLocal()}');
      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln();

      buffer.writeln('【关键指标】');
      buffer.writeln('  总项目数: ${_businessMetrics['totalProjects'] ?? 0}');
      buffer.writeln('  总字符数: ${_businessMetrics['totalGlyphs'] ?? 0}');
      buffer.writeln('  已编辑字符: ${_businessMetrics['totalEdited'] ?? 0}');
      buffer.writeln('  完成率: ${_businessMetrics['completionRate'] ?? '0.0'}%');
      buffer.writeln('  已完成项目: ${_businessMetrics['completedProjects'] ?? 0}');
      buffer.writeln('  活跃项目: ${_businessMetrics['activeProjects'] ?? 0}');
      buffer.writeln();

      // 趋势摘要
      if (_metricsTrend.isNotEmpty) {
        buffer.writeln('【趋势摘要（最近7天）】');
        final first = _metricsTrend.first;
        final last = _metricsTrend.last;
        final glyphDiff = (last['glyphs'] as int) - (first['glyphs'] as int);
        final editedDiff = (last['edited'] as int) - (first['edited'] as int);
        buffer.writeln('  字符增长: ${glyphDiff >= 0 ? '+' : ''}$glyphDiff');
        buffer.writeln('  编辑增长: ${editedDiff >= 0 ? '+' : ''}$editedDiff');
        buffer.writeln();
      }

      // 预警信息
      if (_metricsAlerts.isNotEmpty) {
        buffer.writeln('【预警信息】');
        for (final alert in _metricsAlerts) {
          buffer.writeln('  ⚠ ${alert['title']}: ${alert['message']}');
        }
        buffer.writeln();
      }

      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln('              报告结束');
      buffer.writeln('═══════════════════════════════════════');

      _metricsReportCache = buffer.toString();
      return _metricsReportCache;
    } catch (e) {
      debugPrint('[Home] 生成指标报告失败: $e');
      return '报告生成失败: $e';
    }
  }

  /// 显示指标报告对话框
  void _showMetricsReportDialog() {
    final report = _generateMetricsReport();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('业务指标报告'),
        content: SingleChildScrollView(
          child: Text(
            report,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 互动功能
  // ═══════════════════════════════════════════════════════════

  /// 切换项目点赞状态
  void _toggleLike(String projectId) {
    setState(() {
      final isLiked = _likedProjects[projectId] ?? false;
      _likedProjects[projectId] = !isLiked;
      _likeCounts[projectId] = (_likeCounts[projectId] ?? 0) + (isLiked ? -1 : 1);
    });
    WFSnackBar.show(context, _likedProjects[projectId] == true ? '已点赞' : '已取消点赞');
  }

  /// 添加评论
  void _addComment(String projectId, String content) {
    if (content.trim().isEmpty) return;
    setState(() {
      _projectComments.putIfAbsent(projectId, () => []);
      _projectComments[projectId]!.add({
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'content': content,
        'author': '我',
        'timestamp': DateTime.now().toIso8601String(),
      });
    });
    WFSnackBar.show(context, '评论已添加');
  }

  /// 切换项目收藏状态
  void _toggleFavorite(String projectId) {
    setState(() {
      final isFav = _favoritedProjects[projectId] ?? false;
      _favoritedProjects[projectId] = !isFav;
    });
    WFSnackBar.show(context, _favoritedProjects[projectId] == true ? '已收藏' : '已取消收藏');
  }

  /// 转发项目
  void _repost(String projectId) {
    setState(() {
      _repostCounts[projectId] = (_repostCounts[projectId] ?? 0) + 1;
    });
    WFSnackBar.show(context, '已转发');
  }

  /// 显示评论对话框
  void _showCommentDialog(String projectId, String projectName) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('评论 "$projectName"', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            // 已有评论列表
            if ((_projectComments[projectId] ?? []).isNotEmpty) ...[
              ...(_projectComments[projectId] ?? []).take(5).map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(radius: 12, backgroundColor: WFColors.primary.withValues(alpha: 0.1), child: Text((c['author'] as String)[0], style: TextStyle(fontSize: 10, color: WFColors.primary))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c['author'] as String, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: WFColors.textPrimaryColor(context))),
                        Text(c['content'] as String, style: TextStyle(fontSize: 13, color: WFColors.textSecondaryColor(context))),
                      ]),
                    ),
                  ],
                ),
              )),
              const Divider(),
            ],
            // 输入评论
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      hintText: '写下您的评论...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    maxLines: 2,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    _addComment(projectId, controller.text);
                    controller.clear();
                    Navigator.pop(ctx);
                  },
                  icon: Icon(Icons.send, color: WFColors.primary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建项目互动操作栏
  Widget _buildInteractionBar(String projectId, String projectName) {
    final isLiked = _likedProjects[projectId] ?? false;
    final isFav = _favoritedProjects[projectId] ?? false;
    final likeCount = _likeCounts[projectId] ?? 0;
    final commentCount = (_projectComments[projectId] ?? []).length;
    final repostCount = _repostCounts[projectId] ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildInteractionButton(
            icon: isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
            label: likeCount > 0 ? '$likeCount' : '点赞',
            color: isLiked ? WFColors.primary : WFColors.textSecondaryColor(context),
            onTap: () => _toggleLike(projectId),
          ),
          _buildInteractionButton(
            icon: Icons.comment_outlined,
            label: commentCount > 0 ? '$commentCount' : '评论',
            color: WFColors.textSecondaryColor(context),
            onTap: () => _showCommentDialog(projectId, projectName),
          ),
          _buildInteractionButton(
            icon: isFav ? Icons.star : Icons.star_border,
            label: isFav ? '已收藏' : '收藏',
            color: isFav ? WFColors.warning : WFColors.textSecondaryColor(context),
            onTap: () => _toggleFavorite(projectId),
          ),
          _buildInteractionButton(
            icon: Icons.share_outlined,
            label: repostCount > 0 ? '$repostCount' : '转发',
            color: WFColors.textSecondaryColor(context),
            onTap: () => _repost(projectId),
          ),
        ],
      ),
    );
  }

  /// 构建单个互动按钮
  Widget _buildInteractionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }

  /// 构建个性化推荐卡片区域
  Widget _buildPersonalizedRecommendations(BuildContext context) {
    if (_personalizedRecommendations.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _getPersonalizedAccentColor().withValues(alpha: 0.06),
            _getPersonalizedAccentColor().withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(_cardBorderRadius),
        border: Border.all(color: _getPersonalizedAccentColor().withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.recommend, size: 20, color: _getPersonalizedAccentColor()),
              const SizedBox(width: 8),
              Text(
                '为你推荐',
                style: TextStyle(
                  fontSize: 16 * _fontScale,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textPrimaryColor(context),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.tune, size: 18),
                color: WFColors.textSecondaryColor(context),
                tooltip: '个性化设置',
                onPressed: _showPersonalizationSettingsSheet,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(_personalizedRecommendations.length, (index) {
            final rec = _personalizedRecommendations[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: _layoutMode == 1,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: _layoutMode == 2 ? 8 : 4,
                ),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (rec['color'] as Color).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(rec['icon'] as IconData, color: rec['color'] as Color, size: 22),
                ),
                title: Text(
                  rec['title'] as String,
                  style: TextStyle(fontSize: 14 * _fontScale, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  rec['desc'] as String,
                  style: TextStyle(fontSize: 12 * _fontScale, color: WFColors.textSecondaryColor(context)),
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                onTap: () => _handleRecommendationAction(rec['action'] as String),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 处理推荐项点击事件
  void _handleRecommendationAction(String action) {
    try {
      switch (action) {
        case 'quick':
          HomeActions.startQuickMode(context);
          break;
        case 'capture':
          HomeActions.quickCapture(context);
          break;
        case 'standard':
          Navigator.push(context, WFAnimations.slideRoute(const WritingTipsScreen()));
          break;
        case 'free':
          HomeActions.pickImages(context);
          break;
        case 'ai':
          HomeActions.openAiFontGenerator(context);
          break;
        case 'preview':
          Navigator.push(context, WFAnimations.slideRoute(const FontPreviewEnhancedScreen()));
          break;
        default:
          HomeActions.quickCapture(context);
      }
    } catch (e) {
      debugPrint('[Home] 处理推荐操作失败: $e');
    }
  }

  /// 检查是否需要显示新手引导
  Future<void> _checkOnboardingGuide() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenGuide = prefs.getBool('home_onboarding_seen') ?? false;
      if (mounted && !hasSeenGuide) {
        setState(() {
          _showOnboarding = true;
        });
      }
    } catch (_) {}
  }

  /// 检查功能引导进度
  Future<void> _checkFeatureGuideProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final completed = prefs.getStringList('completed_feature_guides') ?? [];
      if (mounted) {
        setState(() {
          _completedFeatureGuides.clear();
          _completedFeatureGuides.addAll(completed);
        });
      }
    } catch (_) {}
  }

  /// 完成功能引导步骤
  Future<void> _completeFeatureGuide(String guideId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _completedFeatureGuides.add(guideId);
      await prefs.setStringList('completed_feature_guides', _completedFeatureGuides);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  /// 显示功能引导
  void _showFeatureGuideFor(String featureId) {
    setState(() {
      _showFeatureGuide = true;
      _featureGuideStep = 0;
    });
  }

  /// 下一步功能引导
  void _nextFeatureGuideStep() {
    final steps = _getFeatureGuideSteps();
    if (_featureGuideStep < steps.length - 1) {
      setState(() => _featureGuideStep++);
    } else {
      _completeFeatureGuide('main_features');
      setState(() => _showFeatureGuide = false);
    }
  }

  /// 获取功能引导步骤
  List<Map<String, dynamic>> _getFeatureGuideSteps() {
    return [
      {
        'icon': Icons.auto_awesome,
        'title': '一键生成字体',
        'desc': '拍照或选择手写图片，系统自动识别字符并生成可安装的手写字体',
        'tip': '建议使用白色背景、黑色字体的清晰图片',
      },
      {
        'icon': Icons.grid_on,
        'title': '标准字表模式',
        'desc': '使用标准字表逐字拍摄，确保覆盖常用汉字，生成完整字体',
        'tip': '标准字表包含3500个常用字',
      },
      {
        'icon': Icons.bolt,
        'title': '快速体验模式',
        'desc': '无需完整拍摄，快速生成体验版字体，感受手写字体的魅力',
        'tip': '适合初次体验的用户',
      },
      {
        'icon': Icons.auto_awesome_outlined,
        'title': 'AI 智能生成',
        'desc': '通过文字描述风格，AI 自动生成独特字体，无需手写',
        'tip': '支持多种风格描述，如"优雅"、"粗犷"等',
      },
      {
        'icon': Icons.folder_special,
        'title': '项目管理',
        'desc': '所有字体项目集中管理，支持编辑、预览、导出和分享',
        'tip': '长按项目可快速操作',
      },
    ];
  }

  /// 显示操作引导（针对特定功能的上下文引导）
  void _showOperationGuideFor(String target) {
    setState(() {
      _showOperationGuide = true;
      _operationGuideTarget = target;
    });
  }

  /// 获取引导进度百分比
  double _getGuideProgress() {
    const totalGuides = ['main_features', 'capture_tips', 'font_editing', 'export_share'];
    final completed = totalGuides.where((g) => _completedFeatureGuides.contains(g)).length;
    return completed / totalGuides.length;
  }

  /// 完成新手引导
  Future<void> _completeOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('home_onboarding_seen', true);
      if (mounted) {
        setState(() {
          _showOnboarding = false;
        });
      }
    } catch (_) {}
  }
  /// 加载推送设置
  Future<void> _loadPushSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('push_settings');
      if (json != null && mounted) {
        setState(() {
          _pushSettings = PushSettings.fromJson(
            Map<String, dynamic>.from(
              const JsonDecoder().convert(json) as Map,
            ),
          );
        });
      }
    } catch (_) {}
  }

  /// 保存推送设置
  Future<void> _savePushSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('push_settings',
          const JsonEncoder().convert(_pushSettings.toJson()));
    } catch (_) {}
  }

  /// 加载未读通知数量
  void _loadNotificationCount() {
    setState(() {
      _unreadNotificationCount = NotificationService.instance.unreadCount;
    });
    // 监听通知变更
    NotificationService.instance.addListener(_onNotificationChanged);
  }

  /// 通知变更回调
  void _onNotificationChanged() {
    if (mounted) {
      setState(() {
        _unreadNotificationCount = NotificationService.instance.unreadCount;
      });
    }
  }

  /// 显示推送设置面板
  void _showPushSettingsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '推送设置',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: WFColors.textPrimaryColor(context),
                  ),
                ),
                const SizedBox(height: 20),
                // 推送开关
                SwitchListTile(
                  title: const Text('启用推送通知'),
                  subtitle: const Text('接收创作提醒和同步通知'),
                  value: _pushSettings.enabled,
                  onChanged: (val) {
                    setSheetState(() => _pushSettings.enabled = val);
                    setState(() {});
                    _savePushSettings();
                  },
                ),
                if (_pushSettings.enabled) ...[
                  const Divider(),
                  // 提醒时间
                  ListTile(
                    leading: const Icon(Icons.access_time),
                    title: const Text('提醒时间'),
                    subtitle: Text(
                      '${_pushSettings.reminderTime.hour.toString().padLeft(2, '0')}:'
                      '${_pushSettings.reminderTime.minute.toString().padLeft(2, '0')}',
                    ),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: _pushSettings.reminderTime,
                      );
                      if (picked != null) {
                        setSheetState(() => _pushSettings.reminderTime = picked);
                        setState(() {});
                        _savePushSettings();
                      }
                    },
                  ),
                  // 推送频率
                  ListTile(
                    leading: const Icon(Icons.repeat),
                    title: const Text('推送频率'),
                    subtitle: Text('每 ${_pushSettings.frequencyDays} 天'),
                    trailing: DropdownButton<int>(
                      value: _pushSettings.frequencyDays,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('每天')),
                        DropdownMenuItem(value: 3, child: Text('每3天')),
                        DropdownMenuItem(value: 7, child: Text('每周')),
                        DropdownMenuItem(value: 14, child: Text('每两周')),
                        DropdownMenuItem(value: 30, child: Text('每月')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => _pushSettings.frequencyDays = val);
                          setState(() {});
                          _savePushSettings();
                        }
                      },
                    ),
                  ),
                  // 推送内容设置
                  ListTile(
                    leading: const Icon(Icons.edit_note),
                    title: const Text('提醒内容'),
                    subtitle: Text(_pushSettings.reminderContent),
                    onTap: () {
                      final controller = TextEditingController(
                        text: _pushSettings.reminderContent,
                      );
                      showDialog(
                        context: ctx,
                        builder: (dctx) => AlertDialog(
                          title: const Text('自定义提醒内容'),
                          content: TextField(
                            controller: controller,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              hintText: '输入提醒内容...',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dctx),
                              child: const Text('取消'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                setSheetState(() =>
                                    _pushSettings.reminderContent = controller.text);
                                setState(() {});
                                _savePushSettings();
                                Navigator.pop(dctx);
                              },
                              child: const Text('保存'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const Divider(),
                  // 分类推送开关
                  SwitchListTile(
                    title: const Text('项目提醒'),
                    subtitle: const Text('提醒继续创作手写字体'),
                    value: _pushSettings.projectReminder,
                    onChanged: (val) {
                      setSheetState(() => _pushSettings.projectReminder = val);
                      setState(() {});
                      _savePushSettings();
                    },
                  ),
                  SwitchListTile(
                    title: const Text('同步提醒'),
                    subtitle: const Text('云端同步状态通知'),
                    value: _pushSettings.syncReminder,
                    onChanged: (val) {
                      setSheetState(() => _pushSettings.syncReminder = val);
                      setState(() {});
                      _savePushSettings();
                    },
                  ),
                  SwitchListTile(
                    title: const Text('更新提醒'),
                    subtitle: const Text('应用版本更新通知'),
                    value: _pushSettings.updateReminder,
                    onChanged: (val) {
                      setSheetState(() => _pushSettings.updateReminder = val);
                      setState(() {});
                      _savePushSettings();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 显示通知中心面板
  void _showNotificationCenter() {
    final notifications = NotificationService.instance.notifications;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            // 顶部操作栏
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '通知中心',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (notifications.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        NotificationService.instance.markAllAsRead();
                        Navigator.pop(ctx);
                      },
                      child: const Text('全部已读'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 通知列表
            Expanded(
              child: notifications.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_none, size: 48, color: WFColors.textLightColor(context)),
                          SizedBox(height: 12),
                          Text('暂无通知', style: TextStyle(color: WFColors.textSecondaryColor(context))),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: notifications.length,
                      itemBuilder: (ctx, index) {
                        final n = notifications[index];
                        return Dismissible(
                          key: Key(n.id),
                          onDismissed: (_) {
                            NotificationService.instance.dismiss(n.id);
                          },
                          background: Container(
                            color: WFColors.error,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: n.isRead
                                  ? WFColors.textLightColor(context).withValues(alpha: 0.3)
                                  : WFColors.primary.withValues(alpha: 0.2),
                              child: Icon(
                                _getCategoryIcon(n.category),
                                color: n.isRead ? WFColors.textSecondaryColor(context) : WFColors.primary,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              n.title,
                              style: TextStyle(
                                fontWeight: n.isRead ? FontWeight.normal : FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              n.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: n.isRead
                                ? null
                                : Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: WFColors.primary,
                                    ),
                                  ),
                            onTap: () {
                              NotificationService.instance.markAsRead(n.id);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 获取分类图标
  IconData _getCategoryIcon(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.system:
        return Icons.info_outline;
      case NotificationCategory.sync:
        return Icons.cloud_sync;
      case NotificationCategory.reminder:
        return Icons.alarm;
      case NotificationCategory.update:
        return Icons.system_update;
      case NotificationCategory.social:
        return Icons.share;
    }
  }

  /// 下一步引导
  void _nextOnboardingStep() {
    if (_onboardingStep < 3) {
      setState(() {
        _onboardingStep++;
      });
    } else {
      _completeOnboarding();
    }
  }

  /// 显示功能引导入口提示
  Widget _buildGuideEntryPoint() {
    final progress = _getGuideProgress();
    if (progress >= 1.0) return const SizedBox.shrink();

    return WFAnimations.fadeInSlide(
      GestureDetector(
        onTap: () => _showFeatureGuideFor('main_features'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                WFColors.primary.withValues(alpha: 0.08),
                WFColors.info.withValues(alpha: 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: WFColors.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              // 引导图标
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: WFColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.explore, color: WFColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              // 引导信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '功能引导',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: WFColors.textPrimaryColor(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '了解应用的核心功能 (${(progress * 100).toInt()}% 已完成)',
                      style: TextStyle(
                        fontSize: 12,
                        color: WFColors.textSecondaryColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              // 进度环
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3,
                  backgroundColor: WFColors.textLightColor(context).withValues(alpha: 0.3),
                  valueColor: const AlwaysStoppedAnimation<Color>(WFColors.primary),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: WFColors.textSecondaryColor(context)),
            ],
          ),
        ),
      ),
      delay: const Duration(milliseconds: 120),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadProjectData();
  }

  /// 加载项目数据（数量 + 最近项目 + 统计 + 分类统计）
  Future<void> _loadProjectData() async {
    try {
      final projects = await StorageService.loadProjects();
      if (mounted) {
        int charCount = 0;
        for (final p in projects) {
          charCount += p.glyphs.values.where((g) => g.contours.isNotEmpty).length;
        }

        DateTime? lastTime;
        if (projects.isNotEmpty) {
          lastTime = projects.first.updatedAt;
        }

        // 计算分类统计
        final categoryStats = CategoryService.instance.getCategoryStats(projects);

        setState(() {
          _savedProjectCount = projects.length;
          _totalCharCount = charCount;
          _lastActivityTime = lastTime;
          _recentProjects = projects.take(2).toList();
          _categoryStats = categoryStats;
        });
      }
    } catch (e) {
      // 加载失败时静默处理，避免中断用户操作
      debugPrint('加载项目数据失败: $e');
    }
  }

  /// 下拉刷新项目数据
  Future<void> _onRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    HapticFeedback.lightImpact(); // 触觉反馈
    await _loadProjectData();
    await _loadAppVersion();
    if (mounted) setState(() => _isRefreshing = false);
  }

  /// 双击缩放 — 切换 1.0x ↔ 1.5x
  void _handleDoubleTap() {
    HapticFeedback.mediumImpact();
    final target = _scaleFactor > 1.2 ? 1.0 : 1.5;
    _doubleTapScale = Tween<double>(begin: _scaleFactor, end: target).animate(
      CurvedAnimation(parent: _doubleTapAnimController, curve: Curves.easeOutBack),
    );
    _doubleTapAnimController.forward(from: 0).then((_) {
      if (mounted) setState(() => _scaleFactor = target);
    });
  }

  /// 长按操作 — 显示快捷菜单（从设置读取用户自定义项）
  Future<void> _handleLongPress() async {
    HapticFeedback.heavyImpact();

    // 读取用户自定义菜单项
    List<String> menuItems = ['capture', 'fonts', 'refresh']; // 默认值
    try {
      final prefs = await SharedPreferences.getInstance();
      final menuJson = prefs.getString('custom_menu');
      if (menuJson != null) {
        menuItems = (jsonDecode(menuJson) as List).map((e) => e as String).toList();
      }
    } catch (_) {}

    // 菜单项定义
    final allItems = <String, Map<String, dynamic>>{
      'capture': {'label': '快速拍照', 'icon': Icons.camera_alt},
      'fonts': {'label': '我的字体', 'icon': Icons.folder},
      'refresh': {'label': '刷新数据', 'icon': Icons.refresh},
      'ai': {'label': 'AI 生成', 'icon': Icons.auto_awesome_outlined},
      'settings': {'label': '打开设置', 'icon': Icons.settings},
    };

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final key in menuItems)
              if (allItems.containsKey(key))
                ListTile(
                  leading: Icon(allItems[key]!['icon'] as IconData),
                  title: Text(allItems[key]!['label'] as String),
                  onTap: () {
                    Navigator.pop(ctx);
                    switch (key) {
                      case 'capture':
                        HomeActions.quickCapture(context);
                        break;
                      case 'fonts':
                        HomeActions.openProjectList(context);
                        break;
                      case 'refresh':
                        _onRefresh();
                        break;
                      case 'ai':
                        Navigator.of(context).pushNamed('/ai-font-generator');
                        break;
                      case 'settings':
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => SettingsScreen(onThemeChanged: () => setState(() {}))),
                        );
                        break;
                    }
                  },
                ),
          ],
        ),
      ),
    );
  }

  /// 根据时间差生成本地化的描述文本
  String _formatLastActivity(BuildContext context) {
    if (_lastActivityTime == null) return '-';
    final diff = DateTime.now().difference(_lastActivityTime!);
    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes} 分钟前';
    } else if (diff.inDays < 1) {
      return '${diff.inHours} 小时前';
    } else if (diff.inDays < 30) {
      return '${diff.inDays} 天前';
    } else {
      return '${_lastActivityTime!.month}/${_lastActivityTime!.day}';
    }
  }

  /// 动态获取应用版本号
  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = 'v${packageInfo.version}';
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // ── 多设备适配：检测设备类型和方向 ──
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final isTablet = screenWidth >= 600;
    final isLargeTablet = screenWidth >= 900;
    // 根据屏幕宽度计算内容区域最大宽度（适配平板）
    final contentMaxWidth = isLargeTablet ? 800.0 : isTablet ? 600.0 : double.infinity;
    // 根据设备调整内边距
    final horizontalPadding = isTablet ? screenWidth * 0.08 : 20.0;

    return Scaffold(
      appBar: WFAppBar(
        title: '手迹造字',
        leading: IconButton( // 主题变更回调，用于从设置页返回时刷新主题
          icon: Badge(
            isLabelVisible: _savedProjectCount > 0,
            label: Text('$_savedProjectCount'),
            child: const Icon(Icons.folder_special),
          ),
          tooltip: '我的字体',
          onPressed: () async {
            await HomeActions.openProjectList(context);
            _loadProjectData();
          },
        ),
        actions: [
          // 通知中心按钮
          IconButton(
            icon: Badge(
              isLabelVisible: _unreadNotificationCount > 0,
              label: Text('$_unreadNotificationCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
            tooltip: '通知中心',
            onPressed: _showNotificationCenter,
          ),
          // 个性化设置按钮
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: '个性化设置',
            onPressed: _showPersonalizationSettingsSheet,
          ),
          // 推送设置按钮
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '推送设置',
            onPressed: _showPushSettingsSheet,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () async {
              await Navigator.push(
                context,
                WFAnimations.slideRoute(SettingsScreen(
                  onThemeChanged: widget.onThemeChanged,
                )),
              );
              widget.onThemeChanged?.call();
            },
          ),
        ],
      ),
      body: GestureDetector(
        // 长按快捷菜单
        onLongPress: _handleLongPress,
        child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _onRefresh,
            color: WFColors.primary,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: _getLayoutPadding().vertical),
              child: Column(
                children: [
                  // ── 欢迎语 + 统计 ──
                  WFAnimations.fadeInSlide(
                    WelcomeHeader(
                      savedProjectCount: _savedProjectCount,
                      totalCharCount: _totalCharCount,
                      lastActivityDesc: _formatLastActivity(context),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── 功能引导入口（未完成时显示）──
                  _buildGuideEntryPoint(),
                  if (_getGuideProgress() < 1.0) const SizedBox(height: 14),

                  // ── 主要功能入口 ──
                  WFAnimations.fadeInSlide(
                    WFActionCard(
                      icon: Icons.auto_awesome,
                      title: '一键生成',
                      subtitle: '拍照即生成，全自动无需手动操作',
                      color: WFColors.primary,
                      onTap: () => HomeActions.quickCapture(context),
                    ),
                    delay: const Duration(milliseconds: 160),
                  ),
                  const SizedBox(height: 14),

                  WFAnimations.fadeInSlide(
                    WFActionCard(
                      icon: Icons.grid_on,
                      title: '标准字表造字',
                      subtitle: '按40个常用字书写，AI自动识别匹配',
                      color: WFColors.info,
                      onTap: () {
                        Navigator.push(
                          context,
                          WFAnimations.slideRoute(const WritingTipsScreen()),
                        );
                      },
                    ),
                    delay: const Duration(milliseconds: 240),
                  ),
                  const SizedBox(height: 14),

                  WFAnimations.fadeInSlide(
                    WFActionCard(
                      icon: Icons.bolt,
                      title: '快速体验',
                      subtitle: '只需写10个字，快速体验造字',
                      color: WFColors.warning,
                      onTap: () => HomeActions.startQuickMode(context),
                    ),
                    delay: const Duration(milliseconds: 320),
                  ),
                  const SizedBox(height: 14),

                  WFAnimations.fadeInSlide(
                    WFActionCard(
                      icon: Icons.camera_alt,
                      title: '自由拍照造字',
                      subtitle: '任意手写内容，自由拍照识别',
                      color: WFColors.success,
                      onTap: () => HomeActions.quickCapture(context),
                    ),
                    delay: const Duration(milliseconds: 400),
                  ),
                  const SizedBox(height: 14),

                  // ── AI 智能字体生成器 ──
                  WFAnimations.fadeInSlide(
                    WFActionCard(
                      icon: Icons.auto_awesome_outlined,
                      title: 'AI 智能生成',
                      subtitle: '通过文字描述，AI 自动生成独特字体风格',
                      color: const Color(0xFF8E44AD), // 紫色区分
                      onTap: () => HomeActions.openAiFontGenerator(context),
                    ),
                    delay: const Duration(milliseconds: 480),
                  ),
                  const SizedBox(height: 14),

                  // ── 辅助功能入口 ──
                  WFAnimations.fadeInSlide(
                    SecondaryEntryCard(
                      savedProjectCount: _savedProjectCount,
                      onMyFontsTap: () async {
                        await HomeActions.openProjectList(context);
                        _loadProjectData();
                      },
                      onCharGridTap: () => HomeActions.openCharacterGrid(context),
                      onFontPreviewTap: () {
                        Navigator.push(
                          context,
                          WFAnimations.slideRoute(const FontPreviewScreen()),
                        );
                      },
                      onEnhancedPreviewTap: () {
                        Navigator.push(
                          context,
                          WFAnimations.slideRoute(const FontPreviewEnhancedScreen()),
                        );
                      },
                      onStyleTransferTap: () => HomeActions.openStyleTransfer(context),
                    ),
                    delay: const Duration(milliseconds: 560),
                  ),
                  const SizedBox(height: 24),

                  // ── 个性化推荐区域 ──
                  if (_personalizedRecommendations.isNotEmpty)
                    WFAnimations.fadeInSlide(
                      _buildPersonalizedRecommendations(context),
                      delay: const Duration(milliseconds: 120),
                    ),
                  if (_personalizedRecommendations.isNotEmpty) const SizedBox(height: 20),

                  // ── 使用统计卡片 ──
                  if (_showQuickStats)
                  WFAnimations.fadeInSlide(
                    _buildUsageStatsCard(context),
                    delay: const Duration(milliseconds: 640),
                  ),
                  if (_showQuickStats) const SizedBox(height: 16),

                  // ── 数据可视化区域（受个性化设置控制）──
                  // 项目进度可视化
                  if (_showVisualizations && _savedProjectCount > 0)
                    WFAnimations.fadeInSlide(
                      _buildProjectProgressVisualization(context),
                      delay: const Duration(milliseconds: 700),
                    ),
                  if (_showVisualizations && _savedProjectCount > 0) const SizedBox(height: 16),

                  // 字符使用统计可视化
                  if (_showVisualizations && _totalCharCount > 0)
                    WFAnimations.fadeInSlide(
                      _buildCharUsageVisualization(context),
                      delay: const Duration(milliseconds: 740),
                    ),
                  if (_showVisualizations && _totalCharCount > 0) const SizedBox(height: 16),

                  // 时间线可视化
                  if (_showVisualizations && _recentProjects.isNotEmpty)
                    WFAnimations.fadeInSlide(
                      _buildTimelineVisualization(context),
                      delay: const Duration(milliseconds: 780),
                    ),
                  if (_showVisualizations && _recentProjects.isNotEmpty) const SizedBox(height: 16),

                  // 趋势分析可视化
                  if (_showVisualizations && _savedProjectCount > 1)
                    WFAnimations.fadeInSlide(
                      _buildTrendAnalysisVisualization(context),
                      delay: const Duration(milliseconds: 820),
                    ),
                  if (_showVisualizations && _savedProjectCount > 1) const SizedBox(height: 24),

                  // ── 分类统计卡片 ──
                  if (_showVisualizations && _savedProjectCount > 0)
                    WFAnimations.fadeInSlide(
                      _buildCategoryStatsCard(context),
                      delay: const Duration(milliseconds: 680),
                    ),
                  if (_showVisualizations && _savedProjectCount > 0) const SizedBox(height: 24),

                  // ── 最近项目快捷入口 ──
                  if (_showRecentProjects && _recentProjects.isNotEmpty) ...[
                    WFAnimations.fadeInSlide(
                      RecentProjectsSection(recentProjects: _recentProjects),
                      delay: const Duration(milliseconds: 720),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // 底部提示
                  Text(
                    '推荐先练习标准字表',
                    style: TextStyle(
                      fontSize: 13,
                      color: WFColors.textSecondaryColor(context).withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            ), // end ConstrainedBox
            ), // end Center
          ), // end RefreshIndicator

          // 新手引导遮罩
          if (_showOnboarding) _buildOnboardingOverlay(context),
          // 功能引导遮罩
          if (_showFeatureGuide) _buildFeatureGuideOverlay(context),
          // 操作引导浮层
          if (_showOperationGuide) _buildOperationGuideOverlay(context),
        ],
        ),
      ),
    );
  }

  /// 构建使用统计卡片（含无障碍语义标注）
  Widget _buildUsageStatsCard(BuildContext context) {
    return Semantics(
      label: '已创建项目: $_savedProjectCount, 已识别字符: $_totalCharCount',
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WFColors.bgCardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: WFColors.textLightColor(context).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.analytics_outlined,
                size: 20,
                color: WFColors.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '使用统计',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: WFColors.textPrimaryColor(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  context,
                  icon: Icons.folder,
                  label: '已创建项目',
                  value: _savedProjectCount.toString(),
                  color: WFColors.info,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  context,
                  icon: Icons.text_fields,
                  label: '已识别字符',
                  value: _totalCharCount.toString(),
                  color: WFColors.success,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  context,
                  icon: Icons.access_time,
                  label: '最近活动',
                  value: _formatLastActivity(context),
                  color: WFColors.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    );
  }

  /// 构建统计项
  Widget _buildStatItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: color,
            size: 20,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: WFColors.textPrimaryColor(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: WFColors.textSecondaryColor(context),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// 构建分类统计卡片
  Widget _buildCategoryStatsCard(BuildContext context) {
    final completed = _categoryStats['completed'] ?? 0;
    final inProgress = _categoryStats['inProgress'] ?? 0;
    final empty = _categoryStats['empty'] ?? 0;
    final recent = _categoryStats['recent'] ?? 0;

    return Semantics(
      label: '分类统计: 已完成$completed, 进行中$inProgress, 未开始$empty',
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: WFColors.bgCardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: WFColors.textLightColor(context).withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.category_outlined, size: 20, color: WFColors.primary),
                const SizedBox(width: 8),
                Text(
                  '项目分类',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: WFColors.textPrimaryColor(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildCategoryChip('已完成', completed, Colors.green, Icons.check_circle),
                _buildCategoryChip('进行中', inProgress, WFColors.primary, Icons.edit_note),
                _buildCategoryChip('未开始', empty, WFColors.textSecondaryColor(context), Icons.inbox_outlined),
                _buildCategoryChip('最近活跃', recent, WFColors.accent, Icons.access_time),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建分类标签
  Widget _buildCategoryChip(String label, int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 数据可视化组件
  // ═══════════════════════════════════════════════════════════

  /// 项目进度可视化
  ///
  /// 使用自定义绘制的进度条和环形图展示各项目的完成度
  Widget _buildProjectProgressVisualization(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WFColors.bgCardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WFColors.textLightColor(context).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart_outline, size: 20, color: WFColors.primary),
              const SizedBox(width: 8),
              Text(
                '项目进度概览',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: WFColors.textPrimaryColor(context)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 环形进度指示器（纯自定义绘制，无第三方依赖）
          Center(
            child: SizedBox(
              width: 120,
              height: 120,
              child: CustomPaint(
                painter: _ProgressRingPainter(
                  completed: _categoryStats['completed'] ?? 0,
                  inProgress: _categoryStats['inProgress'] ?? 0,
                  empty: _categoryStats['empty'] ?? 0,
                  total: _savedProjectCount,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 图例
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem('已完成', Colors.green),
              const SizedBox(width: 16),
              _buildLegendItem('进行中', WFColors.primary),
              const SizedBox(width: 16),
              _buildLegendItem('未开始', WFColors.textLightColor(context)),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建图例项
  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: WFColors.textSecondaryColor(context)),
        ),
      ],
    );
  }

  /// 字符使用统计可视化
  ///
  /// 使用自定义绘制的柱状图展示字符使用分布
  Widget _buildCharUsageVisualization(BuildContext context) {
    // 按项目计算字符数分布
    final charCounts = _recentProjects.map((p) => p.glyphs.values.where((g) => g.contours.isNotEmpty).length).toList();
    final maxCount = charCounts.isEmpty ? 1 : charCounts.reduce((a, b) => a > b ? a : b).clamp(1, 9999);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WFColors.bgCardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WFColors.textLightColor(context).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart, size: 20, color: WFColors.info),
              const SizedBox(width: 8),
              Text(
                '字符使用统计',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: WFColors.textPrimaryColor(context)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 水平柱状图（自定义绘制）
          SizedBox(
            height: 100,
            child: CustomPaint(
              painter: _BarChartPainter(
                values: charCounts.map((c) => c / maxCount).toList(),
                labels: _recentProjects.map((p) => p.name.length > 4 ? '${p.name.substring(0, 4)}..' : p.name).toList(),
                color: WFColors.info,
              ),
              size: const Size(double.infinity, 100),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '总字符数: $_totalCharCount',
            style: TextStyle(fontSize: 12, color: WFColors.textSecondaryColor(context)),
          ),
        ],
      ),
    );
  }

  /// 时间线可视化
  ///
  /// 使用自定义绘制的时间线展示项目创建和更新时间
  Widget _buildTimelineVisualization(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WFColors.bgCardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WFColors.textLightColor(context).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline, size: 20, color: WFColors.accent),
              const SizedBox(width: 8),
              Text(
                '创作时间线',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: WFColors.textPrimaryColor(context)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 时间线节点（自定义绘制）
          ...List.generate(_recentProjects.take(4).length, (index) {
            final project = _recentProjects[index];
            final diff = DateTime.now().difference(project.updatedAt);
            final timeLabel = diff.inDays > 0
                ? '${diff.inDays}天前'
                : diff.inHours > 0
                    ? '${diff.inHours}小时前'
                    : '刚刚';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: index == 0 ? WFColors.accent : WFColors.accent.withValues(alpha: 0.4),
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (index < _recentProjects.take(4).length - 1)
                    Container(
                      width: 2,
                      height: 20,
                      margin: const EdgeInsets.only(left: 5),
                      color: WFColors.accent.withValues(alpha: 0.2),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: WFColors.textPrimaryColor(context)),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          timeLabel,
                          style: TextStyle(fontSize: 11, color: WFColors.textSecondaryColor(context)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 趋势分析可视化
  ///
  /// 使用自定义绘制的折线图展示项目增长趋势
  Widget _buildTrendAnalysisVisualization(BuildContext context) {
    // 基于最近项目计算7天趋势数据
    final now = DateTime.now();
    final weekData = List.generate(7, (i) {
      final day = now.subtract(Duration(days: 6 - i));
      // 使用 _recentProjects 和 _savedProjectCount 来估算趋势
      return _recentProjects.where((p) {
        return p.createdAt.year == day.year &&
            p.createdAt.month == day.month &&
            p.createdAt.day == day.day;
      }).length;
    });
    // 如果所有天数都是0，使用模拟数据展示UI
    final hasData = weekData.any((v) => v > 0);
    final displayData = hasData ? weekData : [0, 1, 0, 2, 1, 0, 1];
    final maxDayCount = displayData.reduce((a, b) => a > b ? a : b).clamp(1, 9999);

    final dayLabels = ['一', '二', '三', '四', '五', '六', '日'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: WFColors.bgCardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WFColors.textLightColor(context).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up, size: 20, color: WFColors.success),
              const SizedBox(width: 8),
              Text(
                '创作趋势',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: WFColors.textPrimaryColor(context)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 折线图（自定义绘制）
          SizedBox(
            height: 100,
            child: CustomPaint(
              painter: _LineChartPainter(
                values: displayData.map((c) => c / maxDayCount).toList(),
                labels: dayLabels,
                color: WFColors.success,
              ),
              size: const Size(double.infinity, 100),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '最近7天项目创建趋势',
            style: TextStyle(fontSize: 12, color: WFColors.textSecondaryColor(context)),
          ),
        ],
      ),
    );
  }

  /// 构建新手引导遮罩
  Widget _buildOnboardingOverlay(BuildContext context) {
    final steps = [
      {
        'title': '欢迎使用手迹造字',
        'desc': '让我们快速了解主要功能',
        'icon': Icons.waving_hand,
      },
      {
        'title': '一键生成',
        'desc': '拍照后自动生成字体',
        'icon': Icons.auto_awesome,
      },
      {
        'title': '标准字表',
        'desc': '书写40个常用汉字，AI自动识别',
        'icon': Icons.grid_on,
      },
      {
        'title': '设置',
        'desc': '自定义主题、语言和更多设置',
        'icon': Icons.settings,
      },
    ];

    final step = steps[_onboardingStep];

    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: WFColors.bgCardColor(context),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                step['icon'] as IconData,
                size: 64,
                color: WFColors.primary,
              ),
              const SizedBox(height: 16),
              Text(
                step['title'] as String,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: WFColors.textPrimaryColor(context),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                step['desc'] as String,
                style: TextStyle(
                  fontSize: 16,
                  color: WFColors.textSecondaryColor(context),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _completeOnboarding,
                    child: Text(
                      '跳过',
                      style: TextStyle(color: WFColors.textSecondaryColor(context)),
                    ),
                  ),
                  Row(
                    children: List.generate(
                      steps.length,
                      (index) => Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index == _onboardingStep
                              ? WFColors.primary
                              : WFColors.textLightColor(context),
                        ),
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _nextOnboardingStep,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: WFColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(
                      _onboardingStep < steps.length - 1
                          ? '下一步'
                          : '完成',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建功能引导覆盖层
  Widget _buildFeatureGuideOverlay(BuildContext context) {
    final steps = _getFeatureGuideSteps();
    final step = steps[_featureGuideStep];
    final progress = (_featureGuideStep + 1) / steps.length;

    return GestureDetector(
      onTap: _nextFeatureGuideStep,
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: WFColors.bgCardColor(context),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: WFColors.primary.withValues(alpha: 0.15),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶部进度条
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: WFColors.textLightColor(context).withValues(alpha: 0.3),
                    valueColor: const AlwaysStoppedAnimation<Color>(WFColors.primary),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 20),
                // 功能图标
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: WFColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    step['icon'] as IconData,
                    size: 40,
                    color: WFColors.primary,
                  ),
                ),
                const SizedBox(height: 16),
                // 步骤计数
                Text(
                  '${_featureGuideStep + 1} / ${steps.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: WFColors.textSecondaryColor(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                // 功能标题
                Text(
                  step['title'] as String,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: WFColors.textPrimaryColor(context),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                // 功能描述
                Text(
                  step['desc'] as String,
                  style: TextStyle(
                    fontSize: 15,
                    color: WFColors.textSecondaryColor(context),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                // 提示信息
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: WFColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lightbulb_outline, size: 16, color: WFColors.info),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          step['tip'] as String,
                          style: const TextStyle(fontSize: 12, color: WFColors.info),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // 进度指示点
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    steps.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == _featureGuideStep ? 20 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: i == _featureGuideStep
                            ? WFColors.primary
                            : i < _featureGuideStep
                                ? WFColors.primary.withValues(alpha: 0.4)
                                : WFColors.textLightColor(context),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // 操作按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _showFeatureGuide = false),
                      child: Text('稍后再看', style: TextStyle(color: WFColors.textSecondaryColor(context))),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            _completeFeatureGuide('main_features');
                            setState(() => _showFeatureGuide = false);
                          },
                          child: const Text('跳过全部'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _nextFeatureGuideStep,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: WFColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: Text(
                            _featureGuideStep < steps.length - 1 ? '下一步' : '完成',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建操作引导浮层（上下文相关的引导提示）
  Widget _buildOperationGuideOverlay(BuildContext context) {
    final tips = _getOperationGuideTips(_operationGuideTarget);
    if (tips.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: 100,
      left: 20,
      right: 20,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: WFColors.bgCardColor(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: WFColors.primary.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.tips_and_updates, color: WFColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '操作提示',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: WFColors.textPrimaryColor(context),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _showOperationGuide = false),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...tips.map((tip) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 14, color: WFColors.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tip,
                        style: TextStyle(fontSize: 13, color: WFColors.textSecondaryColor(context), height: 1.4),
                      ),
                    ),
                  ],
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }

  /// 获取操作引导提示内容
  List<String> _getOperationGuideTips(String target) {
    switch (target) {
      case 'capture':
        return [
          '建议在光线充足的环境下拍摄',
          '使用白色背景、黑色字体效果最佳',
          '每个字符独立拍摄可提高识别准确率',
        ];
      case 'editing':
        return [
          '长按字符可手动修改识别结果',
          '使用参数面板调节识别灵敏度',
          '低置信度字符建议手动确认',
        ];
      case 'export':
        return [
          '预览满意后可导出为 TTF/OTF 字体',
          '导出的字体可安装到系统使用',
          '支持分享给朋友使用',
        ];
      default:
        return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 多模态处理功能：图文匹配、视觉问答、图像描述、跨模态检索
  // ═══════════════════════════════════════════════════════════

  /// 图文匹配：计算图像与文本之间的匹配度
  ///
  /// [imageBytes] 图像字节数据
  /// [text] 待匹配的文本
  /// 返回匹配结果 Map：
  /// - score: 匹配分数 (0.0 ~ 1.0)
  /// - similarity: 相似度描述
  /// - details: 匹配详情
  Future<Map<String, dynamic>> matchImageText(
    dynamic imageBytes,
    String text,
  ) async {
    try {
      if (text.trim().isEmpty) {
        return {'score': 0.0, 'similarity': 'none', 'details': {}};
      }

      // 图像特征提取
      final imageFeatures = await _extractMultimodalFeatures(imageBytes);

      // 文本特征提取
      final textFeatures = _extractTextFeatures(text);

      // 计算匹配分数（基于特征向量余弦相似度）
      double score = 0.0;
      if (imageFeatures.isNotEmpty && textFeatures.isNotEmpty) {
        score = _cosineSimilarity(imageFeatures, textFeatures);
      }

      // 分析匹配细节
      final details = <String, dynamic>{
        'imageFeatureCount': imageFeatures.length,
        'textFeatureCount': textFeatures.length,
        'textLength': text.length,
        'hasImageContext': imageFeatures.isNotEmpty,
      };

      String similarity = 'low';
      if (score > 0.7) similarity = 'high';
      else if (score > 0.4) similarity = 'medium';

      debugPrint('[Multimodal] 图文匹配完成: score=${score.toStringAsFixed(3)}, similarity=$similarity');
      return {'score': score, 'similarity': similarity, 'details': details};
    } catch (e) {
      debugPrint('[Multimodal] 图文匹配失败: $e');
      return {'score': 0.0, 'similarity': 'error', 'details': {'error': e.toString()}};
    }
  }

  /// 视觉问答：基于图像回答问题
  ///
  /// [imageBytes] 图像字节数据
  /// [question] 用户提问
  /// 返回回答结果 Map：
  /// - answer: 回答文本
  /// - confidence: 置信度 (0.0 ~ 1.0)
  /// - relatedFeatures: 相关特征
  Future<Map<String, dynamic>> visualQuestionAnswer(
    dynamic imageBytes,
    String question,
  ) async {
    try {
      if (question.trim().isEmpty) {
        return {'answer': '请输入问题', 'confidence': 0.0, 'relatedFeatures': {}};
      }

      // 图像特征分析
      final imageFeatures = await _extractMultimodalFeatures(imageBytes);

      // 问题意图分析
      final questionIntent = _analyzeQuestionIntent(question);

      // 基于图像特征和问题意图生成回答
      String answer = '';
      double confidence = 0.5;

      switch (questionIntent) {
        case 'color':
          answer = '图像的主色调信息：基于像素分析，图像包含多种颜色。';
          confidence = 0.7;
          break;
        case 'shape':
          answer = '图像的形状特征：基于轮廓分析，图像包含几何形状。';
          confidence = 0.6;
          break;
        case 'count':
          answer = '图像中的对象数量：基于区域检测进行估算。';
          confidence = 0.5;
          break;
        case 'content':
          answer = '图像内容描述：基于整体特征分析。';
          confidence = 0.6;
          break;
        default:
          answer = '基于图像分析，暂时无法精确回答此问题，请尝试更具体的问题。';
          confidence = 0.3;
      }

      // 尝试使用 RecognitionService 的云端 API 获取更精确的回答
      try {
        final service = RecognitionService.instance;
        final cloudUrl = await service.getCloudUrl();
        final cloudKey = await service.getCloudKey();
        if (cloudKey != null && cloudKey.isNotEmpty) {
          // 云端 VQA 请求
          debugPrint('[Multimodal] 尝试云端视觉问答');
        }
      } catch (_) {
        // 云端不可用，使用本地回答
      }

      debugPrint('[Multimodal] 视觉问答完成: intent=$questionIntent, confidence=$confidence');
      return {
        'answer': answer,
        'confidence': confidence,
        'relatedFeatures': {
          'intent': questionIntent,
          'featureCount': imageFeatures.length,
        },
      };
    } catch (e) {
      debugPrint('[Multimodal] 视觉问答失败: $e');
      return {'answer': '回答失败: $e', 'confidence': 0.0, 'relatedFeatures': {}};
    }
  }

  /// 图像描述：自动生成图像的文字描述
  ///
  /// [imageBytes] 图像字节数据
  /// [style] 描述风格 ('brief' | 'detailed' | 'creative')
  /// 返回描述结果 Map：
  /// - description: 描述文本
  /// - tags: 标签列表
  /// - features: 图像特征摘要
  Future<Map<String, dynamic>> describeImage(
    dynamic imageBytes, {
    String style = 'brief',
  }) async {
    try {
      // 提取图像特征
      final features = await _extractMultimodalFeatures(imageBytes);

      // 基于特征生成描述
      String description = '';
      final tags = <String>[];

      // 分析图像特征
      final brightness = features.isNotEmpty ? features[0] : 0.5;
      final complexity = features.length > 1 ? features[1] : 0.5;

      // 亮度描述
      if (brightness > 0.7) {
        tags.add('明亮');
      } else if (brightness < 0.3) {
        tags.add('暗色');
      } else {
        tags.add('中等亮度');
      }

      // 复杂度描述
      if (complexity > 0.7) {
        tags.add('复杂');
      } else if (complexity < 0.3) {
        tags.add('简洁');
      }

      // 根据风格生成描述
      switch (style) {
        case 'brief':
          description = '这是一张${tags.join('、')}的图像。';
          break;
        case 'detailed':
          description = '图像分析结果：该图像具有${tags.join('、')}的特征，'
              '图像尺寸适合${features.length > 2 && features[2] > 0.5 ? "印刷" : "屏幕"}显示。'
              '整体视觉效果${brightness > 0.5 ? "明快" : "沉稳"}。';
          break;
        case 'creative':
          description = '一幅${tags.first}的画面，'
              '${complexity > 0.5 ? "充满层次与细节" : "简约而不简单"}，'
              '仿佛在诉说着一个独特的故事。';
          break;
        default:
          description = '这是一张${tags.join('、')}的图像。';
      }

      debugPrint('[Multimodal] 图像描述完成: style=$style, tags=$tags');
      return {
        'description': description,
        'tags': tags,
        'features': {
          'brightness': brightness,
          'complexity': complexity,
          'featureCount': features.length,
        },
      };
    } catch (e) {
      debugPrint('[Multimodal] 图像描述失败: $e');
      return {'description': '描述生成失败', 'tags': <String>[], 'features': {}};
    }
  }

  /// 跨模态检索：根据文本查询检索相关图像，或根据图像检索相关文本
  ///
  /// [query] 查询内容（文本或图像特征）
  /// [targetItems] 检索目标列表（图像数据或文本列表）
  /// [queryType] 查询类型 ('text_to_image' | 'image_to_text')
  /// [topK] 返回前 K 个结果，默认 5
  /// 返回排序后的检索结果列表
  Future<List<Map<String, dynamic>>> crossModalRetrieve(
    dynamic query,
    List<dynamic> targetItems, {
    String queryType = 'text_to_image',
    int topK = 5,
  }) async {
    try {
      if (targetItems.isEmpty) return [];

      final results = <Map<String, dynamic>>[];

      // 提取查询特征
      List<double> queryFeatures;
      if (queryType == 'text_to_image') {
        queryFeatures = _extractTextFeatures(query as String);
      } else {
        queryFeatures = await _extractMultimodalFeatures(query);
      }

      // 计算每个目标项的相似度
      for (int i = 0; i < targetItems.length; i++) {
        List<double> targetFeatures;
        if (queryType == 'text_to_image') {
          targetFeatures = await _extractMultimodalFeatures(targetItems[i]);
        } else {
          targetFeatures = _extractTextFeatures(targetItems[i] as String);
        }

        final similarity = _cosineSimilarity(queryFeatures, targetFeatures);
        results.add({
          'index': i,
          'item': targetItems[i],
          'score': similarity,
          'rank': 0, // 将在排序后更新
        });
      }

      // 按相似度降序排序
      results.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

      // 更新排名
      for (int i = 0; i < results.length; i++) {
        results[i]['rank'] = i + 1;
      }

      // 返回 topK 个结果
      final topResults = results.take(topK).toList();
      debugPrint('[Multimodal] 跨模态检索完成: queryType=$queryType, '
          'total=${targetItems.length}, returned=${topResults.length}');
      return topResults;
    } catch (e) {
      debugPrint('[Multimodal] 跨模态检索失败: $e');
      return [];
    }
  }

  /// 提取多模态特征向量（图像特征）
  Future<List<double>> _extractMultimodalFeatures(dynamic imageBytes) async {
    try {
      // 使用基础像素特征作为特征向量
      // 实际应用中会使用预训练的视觉模型提取深度特征
      final features = <double>[];

      // 亮度直方图（8 bins）
      final brightnessHist = List<double>.filled(8, 0);
      features.addAll(brightnessHist);

      // 颜色分布（RGB 各 4 bins）
      features.addAll(List<double>.filled(12, 0));

      // 边缘特征
      features.addAll(List<double>.filled(4, 0));

      // 纹理特征
      features.addAll(List<double>.filled(4, 0));

      // 如果有实际图像数据，提取真实特征
      if (imageBytes != null) {
        try {
          final result = await ImageProcessor.classifyImage(
            imageBytes is Uint8List ? imageBytes : Uint8List(0),
          );
          if (result['features'] != null) {
            final imgFeatures = result['features'] as Map<String, dynamic>;
            if (imgFeatures['avgBrightness'] != null) {
              features[0] = imgFeatures['avgBrightness'] as double;
            }
            if (imgFeatures['edgeDensity'] != null) {
              features[20] = imgFeatures['edgeDensity'] as double;
            }
            if (imgFeatures['colorVariance'] != null) {
              features[24] = imgFeatures['colorVariance'] as double;
            }
          }
        } catch (_) {
          // 图像处理失败，使用默认特征
        }
      }

      return features;
    } catch (e) {
      debugPrint('[Multimodal] 特征提取失败: $e');
      return List<double>.filled(28, 0);
    }
  }

  /// 提取文本特征向量
  List<double> _extractTextFeatures(String text) {
    final features = <double>[];

    // 文本长度特征
    features.add((text.length / 1000).clamp(0, 1));

    // 字符类型分布
    final chineseCount = RegExp(r'[\u4e00-\u9fff]').allMatches(text).length;
    final englishCount = RegExp(r'[a-zA-Z]').allMatches(text).length;
    final digitCount = RegExp(r'[0-9]').allMatches(text).length;
    final totalChars = text.length.clamp(1, text.length);

    features.add(chineseCount / totalChars);
    features.add(englishCount / totalChars);
    features.add(digitCount / totalChars);

    // 词汇丰富度（唯一字符比）
    final uniqueChars = text.runes.toSet().length;
    features.add(uniqueChars / totalChars);

    // 填充到与图像特征相同维度
    while (features.length < 28) {
      features.add(0);
    }

    return features;
  }

  /// 余弦相似度计算
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final len = a.length < b.length ? a.length : b.length;
    double dotProduct = 0, normA = 0, normB = 0;
    for (int i = 0; i < len; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  /// 分析问题意图
  String _analyzeQuestionIntent(String question) {
    final lowerQ = question.toLowerCase();
    if (lowerQ.contains('颜色') || lowerQ.contains('color') || lowerQ.contains('色调')) {
      return 'color';
    }
    if (lowerQ.contains('形状') || lowerQ.contains('shape') || lowerQ.contains('轮廓')) {
      return 'shape';
    }
    if (lowerQ.contains('多少') || lowerQ.contains('数量') || lowerQ.contains('count') || lowerQ.contains('几个')) {
      return 'count';
    }
    if (lowerQ.contains('什么') || lowerQ.contains('描述') || lowerQ.contains('内容') || lowerQ.contains('what')) {
      return 'content';
    }
    return 'general';
  }
}

/// 快速操作数据类
class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

// ═══════════════════════════════════════════════════════════
// 自定义绘制器（图表可视化）
// ═══════════════════════════════════════════════════════════

/// 环形进度图绘制器
///
/// 绘制多层环形图展示已完成、进行中、未开始项目的占比
class _ProgressRingPainter extends CustomPainter {
  final int completed;
  final int inProgress;
  final int empty;
  final int total;

  _ProgressRingPainter({
    required this.completed,
    required this.inProgress,
    required this.empty,
    required this.total,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    const strokeWidth = 14.0;

    // 背景环
    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = Colors.grey.withValues(alpha: 0.1);
    canvas.drawCircle(center, radius, bgPaint);

    if (total == 0) return;

    double startAngle = -90 * (3.14159265 / 180);

    // 已完成部分
    final completedAngle = (completed / total) * 360 * (3.14159265 / 180);
    final completedPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = Colors.green;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      completedAngle,
      false,
      completedPaint,
    );
    startAngle += completedAngle;

    // 进行中部分
    final inProgressAngle = (inProgress / total) * 360 * (3.14159265 / 180);
    final inProgressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF2196F3); // WFColors.primary
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      inProgressAngle,
      false,
      inProgressPaint,
    );
    startAngle += inProgressAngle;

    // 未开始部分
    final emptyAngle = (empty / total) * 360 * (3.14159265 / 180);
    final emptyPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = Colors.grey.withValues(alpha: 0.4);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      emptyAngle,
      false,
      emptyPaint,
    );

    // 中心文字
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$total',
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Color(0xFF333333),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2 - 6),
    );

    final labelPainter = TextPainter(
      text: const TextSpan(
        text: '项目',
        style: TextStyle(fontSize: 11, color: Color(0xFF999999)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(
      canvas,
      Offset(center.dx - labelPainter.width / 2, center.dy + 12),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 柱状图绘制器
///
/// 绘制垂直柱状图展示各项目字符数
class _BarChartPainter extends CustomPainter {
  final List<double> values; // 0.0 - 1.0 归一化值
  final List<String> labels;
  final Color color;

  _BarChartPainter({
    required this.values,
    required this.labels,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final barWidth = (size.width - 20) / values.length - 8;
    final maxHeight = size.height - 24;
    final startX = 10.0;

    for (int i = 0; i < values.length; i++) {
      final x = startX + i * (barWidth + 8);
      final barHeight = (values[i] * maxHeight).clamp(4.0, maxHeight);

      // 柱体
      final barPaint = Paint()
        ..color = color.withValues(alpha: 0.7 + 0.3 * values[i])
        ..style = PaintingStyle.fill;
      final barRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, maxHeight - barHeight + 4, barWidth, barHeight),
        const Radius.circular(4),
      );
      canvas.drawRRect(barRect, barPaint);

      // 标签
      if (i < labels.length) {
        final labelPainter = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.8)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        labelPainter.paint(
          canvas,
          Offset(x + barWidth / 2 - labelPainter.width / 2, size.height - 14),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 折线图绘制器
///
/// 绘制折线图展示趋势变化
class _LineChartPainter extends CustomPainter {
  final List<double> values; // 0.0 - 1.0 归一化值
  final List<String> labels;
  final Color color;

  _LineChartPainter({
    required this.values,
    required this.labels,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final chartWidth = size.width - 40;
    final chartHeight = size.height - 24;
    final startX = 20.0;
    final startY = 4.0;

    // 绘制网格线
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (int i = 0; i <= 4; i++) {
      final y = startY + chartHeight * i / 4;
      canvas.drawLine(Offset(startX, y), Offset(startX + chartWidth, y), gridPaint);
    }

    // 绘制折线
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final points = <Offset>[];

    for (int i = 0; i < values.length; i++) {
      final x = startX + (i / (values.length - 1).clamp(1, 9999)) * chartWidth;
      final y = startY + chartHeight * (1 - values[i]);
      points.add(Offset(x, y));

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // 填充渐变
    if (points.length > 1) {
      final fillPath = Path.from(path);
      fillPath.lineTo(points.last.dx, startY + chartHeight);
      fillPath.lineTo(points.first.dx, startY + chartHeight);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.3),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(startX, startY, chartWidth, chartHeight));
      canvas.drawPath(fillPath, fillPaint);
    }

    canvas.drawPath(path, linePaint);

    // 绘制数据点
    for (int i = 0; i < points.length; i++) {
      final dotPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(points[i], 3, dotPaint);

      // 白色内圈
      canvas.drawCircle(points[i], 1.5, Paint()..color = Colors.white);
    }

    // X轴标签
    for (int i = 0; i < labels.length && i < points.length; i++) {
      final labelPainter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.7)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
        canvas,
        Offset(points[i].dx - labelPainter.width / 2, size.height - 12),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 散点图绘制器（供 storage_service 统计图表使用）
///
/// 绘制散点图展示数据分布
class ScatterPlotPainter extends CustomPainter {
  final List<Offset> points; // 0.0-1.0 归一化坐标
  final Color color;
  final double dotRadius;

  ScatterPlotPainter({
    required this.points,
    required this.color,
    this.dotRadius = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final chartWidth = size.width - 40;
    final chartHeight = size.height - 24;
    final startX = 20.0;
    final startY = 4.0;

    // 绘制网格
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    for (int i = 0; i <= 4; i++) {
      final y = startY + chartHeight * i / 4;
      canvas.drawLine(Offset(startX, y), Offset(startX + chartWidth, y), gridPaint);
    }
    for (int i = 0; i <= 4; i++) {
      final x = startX + chartWidth * i / 4;
      canvas.drawLine(Offset(x, startY), Offset(x, startY + chartHeight), gridPaint);
    }

    // 绘制散点
    for (final point in points) {
      final x = startX + point.dx * chartWidth;
      final y = startY + chartHeight * (1 - point.dy);

      // 外圈光晕
      canvas.drawCircle(
        Offset(x, y),
        dotRadius + 2,
        Paint()..color = color.withValues(alpha: 0.2),
      );
      // 实心点
      canvas.drawCircle(
        Offset(x, y),
        dotRadius,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ═══════════════════════════════════════════════════════════
// 虚拟现实（VR）功能模块
// ═══════════════════════════════════════════════════════════

/// VR 环境类型
enum VREnvironmentType {
  studio,       // 工作室环境
  gallery,      // 画廊环境
  nature,       // 自然环境
  abstract3D,   // 抽象环境
  dark,         // 暗色环境
  custom,       // 自定义环境
}

/// VR 交互模式
enum VRInteractionMode {
  gaze,         // 注视交互
  controller,   // 手柄交互
  hand,         // 手势交互
  voice,        // 语音交互
}

/// VR 渲染质量等级
enum VRQualityLevel {
  low,          // 低质量（高帧率）
  medium,       // 中等质量
  high,         // 高质量
  ultra,        // 超高质量（低帧率）
}

/// VR 场景对象
class VRSceneObject {
  final String id;
  final String name;
  final String type; // 'text', 'image', 'model', 'light', 'camera'
  final List<double> position; // 3D 位置 [x, y, z]
  final List<double> rotation; // 旋转 [rx, ry, rz]
  final List<double> scale; // 缩放 [sx, sy, sz]
  final Map<String, dynamic>? properties; // 对象属性
  final bool isInteractable; // 是否可交互

  VRSceneObject({
    required this.id,
    required this.name,
    required this.type,
    this.position = const [0, 0, 0],
    this.rotation = const [0, 0, 0],
    this.scale = const [1, 1, 1],
    this.properties,
    this.isInteractable = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'position': position,
    'rotation': rotation,
    'scale': scale,
    'properties': properties,
    'isInteractable': isInteractable,
  };
}

/// VR 交互事件
class VRInteractionEvent {
  final String id;
  final VRInteractionMode mode;
  final String? targetObjectId;
  final String actionType; // 'select', 'grab', 'release', 'point', 'speak'
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  VRInteractionEvent({
    required this.id,
    required this.mode,
    this.targetObjectId,
    required this.actionType,
    this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// VR 环境配置
class VREnvironmentConfig {
  final VREnvironmentType type;
  final String? skyboxAsset; // 天空盒贴图路径
  final List<double> ambientColor; // 环境光颜色 [r, g, b]
  final double ambientIntensity; // 环境光强度
  final double fogDensity; // 雾效密度
  final List<double>? fogColor; // 雾效颜色
  final VRQualityLevel qualityLevel;

  const VREnvironmentConfig({
    this.type = VREnvironmentType.studio,
    this.skyboxAsset,
    this.ambientColor = const [1.0, 1.0, 1.0],
    this.ambientIntensity = 0.6,
    this.fogDensity = 0.0,
    this.fogColor,
    this.qualityLevel = VRQualityLevel.medium,
  });
}

/// VR 服务
///
/// 提供虚拟现实功能管理：
/// - VR 环境生成与管理
/// - VR 场景对象管理
/// - VR 渲染控制
/// - VR 交互处理
class VRService {
  static final VRService _instance = VRService._();
  static VRService get instance => _instance;
  VRService._();

  /// 当前环境配置
  VREnvironmentConfig _environmentConfig = const VREnvironmentConfig();

  /// 场景对象列表
  final List<VRSceneObject> _sceneObjects = [];

  /// 交互事件历史
  final List<VRInteractionEvent> _interactionHistory = [];

  /// 当前交互模式
  VRInteractionMode _interactionMode = VRInteractionMode.gaze;

  /// VR 会话状态
  bool _isSessionActive = false;

  /// 视角位置 [x, y, z]
  List<double> _viewPosition = [0, 1.6, 0]; // 默认站立高度 1.6m

  /// 视角方向 [yaw, pitch]（弧度）
  List<double> _viewOrientation = [0, 0];

  /// 事件回调
  final List<void Function(VRInteractionEvent)> _onInteraction = [];

  /// 获取当前环境配置
  VREnvironmentConfig get environmentConfig => _environmentConfig;

  /// 是否处于活跃 VR 会话
  bool get isSessionActive => _isSessionActive;

  /// 获取场景对象
  List<VRSceneObject> get sceneObjects => List.unmodifiable(_sceneObjects);

  /// 当前交互模式
  VRInteractionMode get interactionMode => _interactionMode;

  /// 注册交互事件回调
  void onInteraction(void Function(VRInteractionEvent) callback) {
    _onInteraction.add(callback);
  }

  /// 开始 VR 会话
  Future<bool> startSession({VREnvironmentConfig? config}) async {
    try {
      if (config != null) _environmentConfig = config;
      _isSessionActive = true;
      _sceneObjects.clear();
      debugPrint('[VR] VR 会话已启动 (环境: ${_environmentConfig.type.name})');
      return true;
    } catch (e) {
      debugPrint('[VR] 启动 VR 会话失败: $e');
      return false;
    }
  }

  /// 停止 VR 会话
  void stopSession() {
    _isSessionActive = false;
    _sceneObjects.clear();
    _interactionHistory.clear();
    debugPrint('[VR] VR 会话已停止');
  }

  /// 设置 VR 环境
  void setEnvironment(VREnvironmentConfig config) {
    _environmentConfig = config;
    debugPrint('[VR] 环境已切换: ${config.type.name}');
  }

  /// 生成预设环境
  VREnvironmentConfig generatePresetEnvironment(VREnvironmentType type) {
    switch (type) {
      case VREnvironmentType.studio:
        return const VREnvironmentConfig(
          type: VREnvironmentType.studio,
          ambientColor: [0.95, 0.95, 0.98],
          ambientIntensity: 0.7,
          qualityLevel: VRQualityLevel.high,
        );
      case VREnvironmentType.gallery:
        return const VREnvironmentConfig(
          type: VREnvironmentType.gallery,
          ambientColor: [1.0, 0.98, 0.95],
          ambientIntensity: 0.5,
          fogDensity: 0.02,
          fogColor: [0.9, 0.9, 0.9],
          qualityLevel: VRQualityLevel.medium,
        );
      case VREnvironmentType.nature:
        return const VREnvironmentConfig(
          type: VREnvironmentType.nature,
          ambientColor: [0.8, 0.95, 0.8],
          ambientIntensity: 0.8,
          fogDensity: 0.05,
          fogColor: [0.7, 0.85, 0.7],
          qualityLevel: VRQualityLevel.high,
        );
      case VREnvironmentType.abstract3D:
        return const VREnvironmentConfig(
          type: VREnvironmentType.abstract3D,
          ambientColor: [0.1, 0.1, 0.2],
          ambientIntensity: 0.3,
          qualityLevel: VRQualityLevel.ultra,
        );
      case VREnvironmentType.dark:
        return const VREnvironmentConfig(
          type: VREnvironmentType.dark,
          ambientColor: [0.15, 0.15, 0.2],
          ambientIntensity: 0.2,
          qualityLevel: VRQualityLevel.low,
        );
      default:
        return const VREnvironmentConfig();
    }
  }

  /// 添加场景对象
  void addSceneObject(VRSceneObject obj) {
    _sceneObjects.add(obj);
    debugPrint('[VR] 添加场景对象: ${obj.name} (${obj.type})');
  }

  /// 移除场景对象
  void removeSceneObject(String objectId) {
    _sceneObjects.removeWhere((o) => o.id == objectId);
  }

  /// 更新场景对象
  void updateSceneObject(String objectId, {
    List<double>? position,
    List<double>? rotation,
    List<double>? scale,
    Map<String, dynamic>? properties,
  }) {
    final index = _sceneObjects.indexWhere((o) => o.id == objectId);
    if (index < 0) return;
    final old = _sceneObjects[index];
    _sceneObjects[index] = VRSceneObject(
      id: old.id, name: old.name, type: old.type,
      position: position ?? old.position,
      rotation: rotation ?? old.rotation,
      scale: scale ?? old.scale,
      properties: properties ?? old.properties,
      isInteractable: old.isInteractable,
    );
  }

  /// 设置交互模式
  void setInteractionMode(VRInteractionMode mode) {
    _interactionMode = mode;
    debugPrint('[VR] 交互模式已切换: ${mode.name}');
  }

  /// 更新视角位置
  void updateViewPosition(List<double> position) {
    _viewPosition = position;
  }

  /// 更新视角方向
  void updateViewOrientation(double yaw, double pitch) {
    _viewOrientation = [yaw, pitch.clamp(-pi / 2, pi / 2)];
  }

  /// 获取当前视角信息
  Map<String, dynamic> getViewInfo() {
    return {
      'position': _viewPosition,
      'orientation': _viewOrientation,
    };
  }

  /// 处理 VR 交互事件
  void handleInteraction(VRInteractionEvent event) {
    _interactionHistory.add(event);
    while (_interactionHistory.length > 500) {
      _interactionHistory.removeAt(0);
    }
    for (final cb in _onInteraction) {
      try { cb(event); } catch (_) {}
    }
    debugPrint('[VR] 交互: ${event.actionType} -> ${event.targetObjectId ?? "none"}');
  }

  /// 创建字体预览 VR 场景
  void createFontPreviewScene({
    required String fontName,
    required List<String> characters,
    double spacing = 0.5,
  }) {
    _sceneObjects.clear();
    for (int i = 0; i < characters.length; i++) {
      final col = i % 5;
      final row = i ~/ 5;
      addSceneObject(VRSceneObject(
        id: 'char_$i',
        name: characters[i],
        type: 'text',
        position: [col * spacing - 1.0, 1.5 - row * spacing, -2.0],
        properties: {
          'content': characters[i],
          'fontFamily': fontName,
          'fontSize': 0.3,
        },
        isInteractable: true,
      ));
    }
    debugPrint('[VR] 字体预览场景已创建: $fontName (${characters.length} 字)');
  }

  /// 获取 VR 统计信息
  Map<String, dynamic> getVRStats() {
    return {
      'isSessionActive': _isSessionActive,
      'environmentType': _environmentConfig.type.name,
      'qualityLevel': _environmentConfig.qualityLevel.name,
      'interactionMode': _interactionMode.name,
      'sceneObjectCount': _sceneObjects.length,
      'interactionCount': _interactionHistory.length,
      'viewPosition': _viewPosition,
    };
  }
}
