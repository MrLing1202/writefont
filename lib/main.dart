import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'generated/l10n/app_localizations.dart';
import 'services/locale_service.dart';
import 'models/project.dart';
import 'screens/ai_font_generator_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/auto_generate_screen.dart';
import 'screens/capture_screen.dart';
import 'screens/processing_screen.dart';
import 'screens/preview_screen.dart';
import 'screens/writing_tips_screen.dart';
import 'screens/charset_guide_screen.dart';
import 'screens/ocr_settings_screen.dart';
import 'screens/project_list_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_config_service.dart';
import 'services/recognition_service.dart';
import 'services/image_processor.dart';
import 'theme/app_theme.dart';
import 'dart:typed_data';

// ═══════════════════════════════════════════════════════════
// 通知服务：本地通知、通知分类、优先级、历史记录
// ═══════════════════════════════════════════════════════════

/// 通知优先级枚举
enum NotificationPriority { low, normal, high, urgent }

/// 通知分类枚举
enum NotificationCategory {
  system,      // 系统通知
  sync,        // 同步通知
  reminder,    // 提醒通知
  update,      // 更新通知
  social,      // 社交通知（如分享）
}

/// 通知消息数据模型
class AppNotification {
  final String id;
  final String title;
  final String body;
  final NotificationCategory category;
  final NotificationPriority priority;
  final DateTime timestamp;
  bool isRead;
  final Map<String, dynamic>? payload;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.category = NotificationCategory.system,
    this.priority = NotificationPriority.normal,
    DateTime? timestamp,
    this.isRead = false,
    this.payload,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'category': category.name,
        'priority': priority.name,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead,
        'payload': payload,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        category: NotificationCategory.values.firstWhere(
          (e) => e.name == json['category'],
          orElse: () => NotificationCategory.system,
        ),
        priority: NotificationPriority.values.firstWhere(
          (e) => e.name == json['priority'],
          orElse: () => NotificationPriority.normal,
        ),
        timestamp: DateTime.parse(json['timestamp'] as String),
        isRead: json['isRead'] as bool? ?? false,
        payload: json['payload'] as Map<String, dynamic>?,
      );
}

/// 本地通知服务
///
/// 功能：
/// - 本地通知管理（无需网络依赖）
/// - 通知分类（系统、同步、提醒、更新、社交）
/// - 通知优先级（低、普通、高、紧急）
/// - 通知历史记录（持久化存储）
/// - 项目分类管理（自动分类、手动分类、分类统计）
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;
  NotificationService._();

  final List<AppNotification> _notifications = [];
  static const int _maxNotifications = 200;
  static const String _keyNotifications = 'app_notifications';
  static const String _keyUnreadCount = 'app_unread_count';

  /// 通知变更回调列表
  final List<VoidCallback> _listeners = [];

  /// 添加监听器
  void addListener(VoidCallback listener) => _listeners.add(listener);

  /// 移除监听器
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  /// 通知所有监听器
  void _notifyListeners() {
    for (final listener in _listeners) {
      try {
        listener();
      } catch (_) {}
    }
  }

  /// 获取所有通知
  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  /// 获取未读通知数量
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  /// 按分类获取通知
  List<AppNotification> getByCategory(NotificationCategory category) =>
      _notifications.where((n) => n.category == category).toList();

  /// 按优先级获取通知
  List<AppNotification> getByPriority(NotificationPriority priority) =>
      _notifications.where((n) => n.priority == priority).toList();

  /// 初始化通知服务，从本地恢复通知历史
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_keyNotifications);
      if (json != null) {
        final list = jsonDecode(json) as List;
        _notifications.clear();
        _notifications.addAll(
          list.map((e) => AppNotification.fromJson(e as Map<String, dynamic>)),
        );
      }
      debugPrint('[NotificationService] 初始化完成，${_notifications.length} 条通知');
    } catch (e) {
      debugPrint('[NotificationService] 初始化失败: $e');
    }
  }

  /// 发送本地通知
  ///
  /// [title] 通知标题
  /// [body] 通知内容
  /// [category] 通知分类
  /// [priority] 通知优先级
  /// [payload] 附带数据
  Future<void> show({
    required String title,
    required String body,
    NotificationCategory category = NotificationCategory.system,
    NotificationPriority priority = NotificationPriority.normal,
    Map<String, dynamic>? payload,
  }) async {
    try {
      final notification = AppNotification(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        body: body,
        category: category,
        priority: priority,
        payload: payload,
      );

      _notifications.insert(0, notification);
      // 限制通知数量
      while (_notifications.length > _maxNotifications) {
        _notifications.removeLast();
      }

      await _saveNotifications();
      _notifyListeners();

      debugPrint('[NotificationService] 通知已发送: $title (${category.name})');
    } catch (e) {
      debugPrint('[NotificationService] 发送通知失败: $e');
    }
  }

  /// 标记单条通知为已读
  Future<void> markAsRead(String notificationId) async {
    try {
      final notification = _notifications.firstWhere(
        (n) => n.id == notificationId,
      );
      notification.isRead = true;
      await _saveNotifications();
      _notifyListeners();
    } catch (_) {}
  }

  /// 标记所有通知为已读
  Future<void> markAllAsRead() async {
    for (final n in _notifications) {
      n.isRead = true;
    }
    await _saveNotifications();
    _notifyListeners();
  }

  /// 删除单条通知
  Future<void> dismiss(String notificationId) async {
    _notifications.removeWhere((n) => n.id == notificationId);
    await _saveNotifications();
    _notifyListeners();
  }

  /// 清除所有通知
  Future<void> clearAll() async {
    _notifications.clear();
    await _saveNotifications();
    _notifyListeners();
  }

  /// 清除指定分类的通知
  Future<void> clearCategory(NotificationCategory category) async {
    _notifications.removeWhere((n) => n.category == category);
    await _saveNotifications();
    _notifyListeners();
  }

  /// 持久化通知列表
  Future<void> _saveNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_notifications.map((e) => e.toJson()).toList());
      await prefs.setString(_keyNotifications, json);
      await prefs.setInt(_keyUnreadCount, unreadCount);
    } catch (e) {
      debugPrint('[NotificationService] 保存通知失败: $e');
    }
  }
}

// ═══════════════════════════════════════════════════════════
// 项目分类服务：自动分类、手动分类、分类统计、分类管理
// ═══════════════════════════════════════════════════════════

/// 项目分类枚举
enum ProjectCategory {
  all,         // 全部
  recent,      // 最近编辑（7天内）
  inProgress,  // 进行中（有编辑但未完成）
  completed,   // 已完成（进度>=80%）
  empty,       // 未开始（无编辑）
  small,       // 小型项目（<20字符）
  medium,      // 中型项目（20-50字符）
  large,       // 大型项目（>50字符）
  custom,      // 自定义分类
}

/// 项目分类数据模型
class ProjectCategoryData {
  final String id;
  final String name;
  final String? description;
  final String? icon;
  final List<String> projectIds;
  final DateTime createdAt;

  ProjectCategoryData({
    required this.id,
    required this.name,
    this.description,
    this.icon,
    List<String>? projectIds,
    DateTime? createdAt,
  })  : projectIds = projectIds ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'icon': icon,
        'projectIds': projectIds,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ProjectCategoryData.fromJson(Map<String, dynamic> json) =>
      ProjectCategoryData(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        icon: json['icon'] as String?,
        projectIds: (json['projectIds'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// 项目分类服务
///
/// 功能：
/// - 自动分类（根据项目属性自动归类）
/// - 手动分类（用户自定义分类）
/// - 分类统计（各类别项目数量和进度）
/// - 分类管理（增删改查分类）
class CategoryService {
  static final CategoryService _instance = CategoryService._();
  static CategoryService get instance => _instance;
  CategoryService._();

  static const String _customCategoriesKey = 'custom_categories';
  static const String _projectCategoriesKey = 'project_categories';
  List<ProjectCategoryData> _customCategories = [];
  Map<String, List<String>> _projectCategoryMap = {}; // projectId -> categoryIds

  /// 初始化分类服务
  Future<void> init() async {
    await _loadCustomCategories();
    await _loadProjectCategoryMap();
  }

  /// 加载自定义分类
  Future<void> _loadCustomCategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_customCategoriesKey);
      if (json != null) {
        final list = jsonDecode(json) as List;
        _customCategories = list
            .map((e) => ProjectCategoryData.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('[CategoryService] 加载自定义分类失败: $e');
    }
  }

  /// 保存自定义分类
  Future<void> _saveCustomCategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_customCategories.map((e) => e.toJson()).toList());
      await prefs.setString(_customCategoriesKey, json);
    } catch (e) {
      debugPrint('[CategoryService] 保存自定义分类失败: $e');
    }
  }

  /// 加载项目分类映射
  Future<void> _loadProjectCategoryMap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_projectCategoriesKey);
      if (json != null) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        _projectCategoryMap = map.map(
          (k, v) => MapEntry(k, (v as List).map((e) => e as String).toList()),
        );
      }
    } catch (e) {
      debugPrint('[CategoryService] 加载项目分类映射失败: $e');
    }
  }

  /// 保存项目分类映射
  Future<void> _saveProjectCategoryMap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_projectCategoryMap);
      await prefs.setString(_projectCategoriesKey, json);
    } catch (e) {
      debugPrint('[CategoryService] 保存项目分类映射失败: $e');
    }
  }

  /// 自动分类项目（根据项目属性自动归类到内置分类）
  ///
  /// 返回项目所属的自动分类列表
  List<ProjectCategory> autoClassify(dynamic project) {
    final categories = <ProjectCategory>[];
    final now = DateTime.now();

    // 时间分类
    if (now.difference(project.updatedAt).inDays <= 7) {
      categories.add(ProjectCategory.recent);
    }

    // 进度分类
    final totalGlyphs = project.glyphs.length;
    if (totalGlyphs > 0) {
      final editedCount = project.glyphs.values
          .where((g) => g.contours.isNotEmpty)
          .length;
      final progress = editedCount / totalGlyphs;

      if (progress >= 0.8) {
        categories.add(ProjectCategory.completed);
      } else if (editedCount > 0) {
        categories.add(ProjectCategory.inProgress);
      } else {
        categories.add(ProjectCategory.empty);
      }
    } else {
      categories.add(ProjectCategory.empty);
    }

    // 规模分类
    if (totalGlyphs < 20) {
      categories.add(ProjectCategory.small);
    } else if (totalGlyphs <= 50) {
      categories.add(ProjectCategory.medium);
    } else {
      categories.add(ProjectCategory.large);
    }

    return categories;
  }

  /// 创建自定义分类
  Future<ProjectCategoryData> createCategory({
    required String name,
    String? description,
    String? icon,
  }) async {
    final category = ProjectCategoryData(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      description: description,
      icon: icon,
    );
    _customCategories.add(category);
    await _saveCustomCategories();
    debugPrint('[CategoryService] 创建分类: $name');
    return category;
  }

  /// 更新自定义分类
  Future<void> updateCategory(String categoryId, {
    String? name,
    String? description,
    String? icon,
  }) async {
    final index = _customCategories.indexWhere((c) => c.id == categoryId);
    if (index >= 0) {
      final old = _customCategories[index];
      _customCategories[index] = ProjectCategoryData(
        id: old.id,
        name: name ?? old.name,
        description: description ?? old.description,
        icon: icon ?? old.icon,
        projectIds: old.projectIds,
        createdAt: old.createdAt,
      );
      await _saveCustomCategories();
    }
  }

  /// 删除自定义分类
  Future<void> deleteCategory(String categoryId) async {
    _customCategories.removeWhere((c) => c.id == categoryId);
    // 同时移除所有项目对该分类的引用
    for (final entry in _projectCategoryMap.entries) {
      entry.value.remove(categoryId);
    }
    await _saveCustomCategories();
    await _saveProjectCategoryMap();
  }

  /// 获取所有自定义分类
  List<ProjectCategoryData> get customCategories =>
      List.unmodifiable(_customCategories);

  /// 将项目添加到自定义分类
  Future<void> addProjectToCategory(String projectId, String categoryId) async {
    final categoryIds = _projectCategoryMap[projectId] ?? [];
    if (!categoryIds.contains(categoryId)) {
      categoryIds.add(categoryId);
      _projectCategoryMap[projectId] = categoryIds;
      await _saveProjectCategoryMap();
    }
  }

  /// 将项目从自定义分类中移除
  Future<void> removeProjectFromCategory(String projectId, String categoryId) async {
    final categoryIds = _projectCategoryMap[projectId];
    if (categoryIds != null) {
      categoryIds.remove(categoryId);
      if (categoryIds.isEmpty) {
        _projectCategoryMap.remove(projectId);
      }
      await _saveProjectCategoryMap();
    }
  }

  /// 获取项目所属的自定义分类 ID 列表
  List<String> getProjectCategories(String projectId) {
    return _projectCategoryMap[projectId] ?? [];
  }

  /// 获取分类统计信息
  ///
  /// [projects] 所有项目列表
  /// 返回各类别的项目数量 Map
  Map<String, int> getCategoryStats(List<dynamic> projects) {
    final stats = <String, int>{
      'all': projects.length,
      'recent': 0,
      'inProgress': 0,
      'completed': 0,
      'empty': 0,
      'small': 0,
      'medium': 0,
      'large': 0,
    };

    for (final project in projects) {
      final categories = autoClassify(project);
      for (final cat in categories) {
        stats[cat.name] = (stats[cat.name] ?? 0) + 1;
      }
    }

    // 统计自定义分类
    for (final customCat in _customCategories) {
      stats['custom_${customCat.id}'] = customCat.projectIds.length;
    }

    return stats;
  }

  /// 按分类过滤项目列表
  ///
  /// [projects] 所有项目列表
  /// [category] 目标分类
  /// [categoryId] 自定义分类 ID（当 category 为 custom 时使用）
  List<dynamic> filterByCategory(
    List<dynamic> projects,
    ProjectCategory category, {
    String? categoryId,
  }) {
    if (category == ProjectCategory.all) return projects;

    return projects.where((project) {
      if (category == ProjectCategory.custom && categoryId != null) {
        final projectCategories = getProjectCategories(project.id);
        return projectCategories.contains(categoryId);
      }
      final autoCategories = autoClassify(project);
      return autoCategories.contains(category);
    }).toList();
  }
}

// ═══════════════════════════════════════════════════════════
// 分析功能：使用分析、性能分析、错误分析、用户行为分析
// ═══════════════════════════════════════════════════════════

/// 应用分析服务（轻量级，无需第三方依赖）
///
/// 功能：
/// - 使用分析：记录页面访问、功能使用频率
/// - 性能分析：记录启动时间、页面切换延迟
/// - 错误分析：记录未捕获异常和用户操作上下文
/// - 用户行为分析：记录操作路径和会话时长
class AppAnalytics {
  // 使用分析
  static final Map<String, int> _pageViews = {};
  static final Map<String, int> _featureUsage = {};

  // 性能分析
  static DateTime? _appStartTime;
  static final List<Map<String, dynamic>> _performanceEvents = [];
  static const int _maxPerfEvents = 200;

  // 错误分析
  static final List<Map<String, dynamic>> _errorEvents = [];
  static const int _maxErrorEvents = 100;

  // 用户行为分析
  static final List<String> _actionPath = [];
  static const int _maxActionPath = 50;
  static DateTime? _sessionStartTime;
  static int _sessionCount = 0;
  static String? _currentPage;

  /// 初始化分析（应用启动时调用）
  static void init() {
    _appStartTime = DateTime.now();
    _sessionStartTime = DateTime.now();
    _sessionCount++;
    debugPrint('[Analytics] 会话开始 #$_sessionCount');
  }

  // ── 使用分析 ──

  /// 记录页面访问
  static void trackPageView(String pageName) {
    _pageViews[pageName] = (_pageViews[pageName] ?? 0) + 1;
    _currentPage = pageName;
    _recordAction('page:$pageName');
    debugPrint('[Analytics] 页面访问: $pageName (第${_pageViews[pageName]}次)');
  }

  /// 记录功能使用
  static void trackFeature(String featureName) {
    _featureUsage[featureName] = (_featureUsage[featureName] ?? 0) + 1;
    _recordAction('feature:$featureName');
    debugPrint('[Analytics] 功能使用: $featureName');
  }

  /// 获取使用分析报告
  static Map<String, dynamic> getUsageReport() {
    return {
      'pageViews': Map<String, int>.from(_pageViews),
      'featureUsage': Map<String, int>.from(_featureUsage),
      'totalPageViews': _pageViews.values.fold(0, (a, b) => a + b),
      'totalFeatureUsage': _featureUsage.values.fold(0, (a, b) => a + b),
      'mostVisitedPage': _getMaxKey(_pageViews),
      'mostUsedFeature': _getMaxKey(_featureUsage),
    };
  }

  // ── 性能分析 ──

  /// 记录性能事件
  static void trackPerformance(String event, {Duration? duration, Map<String, dynamic>? metadata}) {
    _performanceEvents.add({
      'timestamp': DateTime.now().toIso8601String(),
      'event': event,
      'durationMs': duration?.inMicroseconds.toDouble().clamp(0, double.infinity) ?? 0,
      if (metadata != null) ...metadata,
    });
    if (_performanceEvents.length > _maxPerfEvents) {
      _performanceEvents.removeAt(0);
    }
  }

  /// 记录页面切换延迟
  static void trackPageTransition(String fromPage, String toPage, Duration duration) {
    trackPerformance('page_transition', duration: duration, metadata: {
      'from': fromPage,
      'to': toPage,
    });
  }

  /// 获取应用运行时长
  static Duration? get uptime {
    if (_appStartTime == null) return null;
    return DateTime.now().difference(_appStartTime!);
  }

  /// 获取性能分析报告
  static Map<String, dynamic> getPerformanceReport() {
    final durations = _performanceEvents
        .where((e) => (e['durationMs'] as double) > 0)
        .map((e) => e['durationMs'] as double)
        .toList();

    double avgDuration = 0;
    if (durations.isNotEmpty) {
      avgDuration = durations.reduce((a, b) => a + b) / durations.length;
    }

    return {
      'eventCount': _performanceEvents.length,
      'avgDurationMs': avgDuration,
      'uptime': uptime?.inSeconds,
      'recentEvents': _performanceEvents.take(20).toList(),
    };
  }

  // ── 错误分析 ──

  /// 记录错误事件
  static void trackError(String error, {String? context, StackTrace? stackTrace}) {
    _errorEvents.add({
      'timestamp': DateTime.now().toIso8601String(),
      'error': error,
      if (context != null) 'context': context,
      'currentPage': _currentPage,
      'lastActions': _actionPath.take(5).toList(),
    });
    if (_errorEvents.length > _maxErrorEvents) {
      _errorEvents.removeAt(0);
    }
    debugPrint('[Analytics] 错误: $error${context != null ? ' ($context)' : ''}');
  }

  /// 获取错误分析报告
  static Map<String, dynamic> getErrorReport() {
    // 按错误类型分组
    final errorTypes = <String, int>{};
    for (final e in _errorEvents) {
      final errorStr = e['error'] as String;
      final type = errorStr.length > 50 ? errorStr.substring(0, 50) : errorStr;
      errorTypes[type] = (errorTypes[type] ?? 0) + 1;
    }

    return {
      'totalErrors': _errorEvents.length,
      'errorTypes': errorTypes,
      'recentErrors': _errorEvents.take(20).toList(),
    };
  }

  // ── 用户行为分析 ──

  /// 记录用户操作
  static void _recordAction(String action) {
    _actionPath.add(action);
    if (_actionPath.length > _maxActionPath) {
      _actionPath.removeAt(0);
    }
  }

  /// 记录用户自定义操作
  static void trackAction(String action) {
    _recordAction(action);
    debugPrint('[Analytics] 用户操作: $action');
  }

  /// 获取会话信息
  static Map<String, dynamic> getSessionInfo() {
    final sessionDuration = _sessionStartTime != null
        ? DateTime.now().difference(_sessionStartTime!).inSeconds
        : 0;

    return {
      'sessionCount': _sessionCount,
      'sessionDurationSeconds': sessionDuration,
      'currentPage': _currentPage,
      'recentActions': List<String>.from(_actionPath),
      'actionPathLength': _actionPath.length,
    };
  }

  /// 获取完整分析报告（合并所有维度）
  static Map<String, dynamic> getFullReport() {
    return {
      'reportTime': DateTime.now().toIso8601String(),
      'session': getSessionInfo(),
      'usage': getUsageReport(),
      'performance': getPerformanceReport(),
      'errors': getErrorReport(),
    };
  }

  /// 导出分析数据为 JSON
  static String exportAnalyticsData() {
    return const JsonEncoder.withIndent('  ').convert(getFullReport());
  }

  /// 清除所有分析数据
  static void clearAll() {
    _pageViews.clear();
    _featureUsage.clear();
    _performanceEvents.clear();
    _errorEvents.clear();
    _actionPath.clear();
  }

  /// 辅助方法：获取 Map 中值最大的 key
  static String? _getMaxKey(Map<String, int> map) {
    if (map.isEmpty) return null;
    return map.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}

/// 应用主导航页面 - 包含底部导航栏和页面状态保持
class MainNavigationPage extends StatefulWidget {
  final VoidCallback? onThemeChanged;
  
  const MainNavigationPage({super.key, this.onThemeChanged});
  
  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIndex = 0;
  late final List<Widget> _pages;
  
  @override
  void initState() {
    super.initState();
    _pages = [
      HomeScreen(onThemeChanged: widget.onThemeChanged),
      const ProjectListScreen(),
      const WritingTipsScreen(),
      SettingsScreen(onThemeChanged: widget.onThemeChanged),
    ];
  }
  
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            final pages = ['home', 'my-fonts', 'writing-tips', 'settings'];
            AppAnalytics.trackPageView(pages[index]);
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          selectedItemColor: Theme.of(context).primaryColor,
          unselectedItemColor: WFColors.textSecondary,
          selectedFontSize: 12,
          unselectedFontSize: 10,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.home_outlined),
              activeIcon: const Icon(Icons.home),
              label: l10n.appName,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.folder_outlined),
              activeIcon: const Icon(Icons.folder),
              label: l10n.myFonts,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.tips_and_updates_outlined),
              activeIcon: const Icon(Icons.tips_and_updates),
              label: l10n.writingTips,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.settings_outlined),
              activeIcon: const Icon(Icons.settings),
              label: l10n.settings,
            ),
          ],
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppAnalytics.init(); // 初始化分析服务
  await NotificationService.instance.init(); // 初始化通知服务
  await CategoryService.instance.init(); // 初始化分类服务
  FlutterError.onError = (details) {
    AppAnalytics.trackError(
      details.exceptionAsString(),
      context: details.library,
      stackTrace: details.stack,
    );
  };
  runApp(const WriteFontApp());
}

// ── 无障碍：键盘快捷键 Intent 定义 ──
class _ToggleHighContrastIntent extends Intent {
  const _ToggleHighContrastIntent();
}

class _IncreaseFontIntent extends Intent {
  const _IncreaseFontIntent();
}

class _DecreaseFontIntent extends Intent {
  const _DecreaseFontIntent();
}

class WriteFontApp extends StatefulWidget {
  const WriteFontApp({super.key});

  @override
  State<WriteFontApp> createState() => _WriteFontAppState();
}

class _WriteFontAppState extends State<WriteFontApp> with WidgetsBindingObserver {
  String _themeModeStr = AppConfigService.defaultThemeMode;
  bool _onboardingSeen = false;
  bool _onboardingChecked = false;
  Locale _locale = const Locale('zh');
  bool _useBottomNav = true; // 是否使用底部导航栏
  bool _isAppInForeground = true; // 电池优化：追踪应用前后台状态

  // ── 无障碍设置 ──
  bool _highContrastMode = false;       // 高对比度模式
  double _accessibilityFontScale = 1.0; // 无障碍字体缩放（独立于主题字体缩放）
  bool _reducedMotion = false;          // 减少动画效果（屏幕阅读器友好）

  /// SharedPreferences 缓存，避免重复同步 I/O
  static SharedPreferences? _prefsCache;

  /// 获取 SharedPreferences 实例（带缓存 + 5秒超时）
  static Future<SharedPreferences> getPrefs() async {
    _prefsCache ??= await SharedPreferences.getInstance()
        .timeout(const Duration(seconds: 5), onTimeout: () {
      // 超时后使用默认值，不阻塞UI
      throw Exception('SharedPreferences init timed out');
    });
    return _prefsCache!;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadThemeMode();
    _loadLocale();
    _checkOnboarding();
    _loadNavigationPreference();
    _loadAccessibilitySettings();
    // 3秒兜底：如果 _checkOnboarding 还没完成，强制标记为已检查，避免永久 loading
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_onboardingChecked) {
        setState(() {
          _onboardingChecked = true;
        });
      }
    });
  }

  /// 加载导航偏好设置
  Future<void> _loadNavigationPreference() async {
    try {
      final prefs = await getPrefs();
      if (mounted) {
        setState(() {
          _useBottomNav = prefs.getBool('use_bottom_nav') ?? true;
        });
      }
    } catch (_) {}
  }

  /// 加载无障碍设置
  Future<void> _loadAccessibilitySettings() async {
    try {
      final prefs = await getPrefs();
      if (mounted) {
        setState(() {
          _highContrastMode = prefs.getBool('high_contrast_mode') ?? false;
          _accessibilityFontScale = prefs.getDouble('accessibility_font_scale') ?? 1.0;
          _reducedMotion = prefs.getBool('reduced_motion') ?? false;
        });
      }
    } catch (_) {}
  }

  /// 检查是否已看过新手引导
  Future<void> _checkOnboarding() async {
    try {
      final prefs = await getPrefs();
      final seen = prefs.getBool('onboarding_seen') ?? false;
      if (mounted) {
        setState(() {
          _onboardingSeen = seen;
          _onboardingChecked = true;
        });
      }
    } catch (e) {
      // getPrefs 超时或其他错误，直接标记为已检查，避免永久 loading
      if (mounted) {
        setState(() {
          _onboardingChecked = true;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RecognitionService.instance.dispose(); // 释放识别服务资源
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // 电池优化：应用回到前台时恢复状态
        _isAppInForeground = true;
        AppAnalytics.trackFeature('app_resumed');
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // 电池优化：应用进入后台时释放非必要资源
        _isAppInForeground = false;
        // 清理轮廓提取缓存，释放内存
        ImageProcessor.clearContourCache();
        AppAnalytics.trackFeature('app_paused');
        break;
      case AppLifecycleState.detached:
        RecognitionService.instance.dispose();
        ImageProcessor.clearContourCache();
        AppAnalytics.trackFeature('app_detached');
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  /// 加载主题模式设置
  Future<void> _loadThemeMode() async {
    final themeMode = await AppConfigService.instance.getThemeMode();
    if (mounted) {
      setState(() => _themeModeStr = themeMode);
    }
  }

  /// 加载语言设置
  Future<void> _loadLocale() async {
    final localeService = LocaleService.instance;
    await localeService.init();
    localeService.addListener(() {
      if (mounted) {
        setState(() => _locale = localeService.locale);
      }
    });
    if (mounted) {
      setState(() => _locale = localeService.locale);
    }
  }

  /// 切换高对比度模式
  void _toggleHighContrast() {
    setState(() => _highContrastMode = !_highContrastMode);
    _saveAccessibilitySetting('high_contrast_mode', _highContrastMode);
    AppAnalytics.trackFeature('toggle_high_contrast');
  }

  /// 调整无障碍字体缩放
  void _adjustAccessibilityFont(double delta) {
    final newScale = (_accessibilityFontScale + delta).clamp(0.8, 2.0);
    if (newScale == _accessibilityFontScale) return;
    setState(() => _accessibilityFontScale = newScale);
    _saveAccessibilitySetting('accessibility_font_scale', _accessibilityFontScale);
    AppAnalytics.trackFeature('adjust_accessibility_font');
  }

  /// 保存无障碍设置
  Future<void> _saveAccessibilitySetting(String key, dynamic value) async {
    try {
      final prefs = await getPrefs();
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      }
    } catch (_) {}
  }

  /// 根据字符串获取 ThemeMode
  ThemeMode get _themeMode {
    switch (_themeModeStr) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  /// 构建浅色主题 — 使用 WFColors 统一色彩方案
  static ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: null, // 使用系统字体
      colorScheme: ColorScheme.fromSeed(
        seedColor: WFColors.primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: WFColors.primary,
        onPrimary: Colors.white,
        secondary: WFColors.accent,
        surface: WFColors.bgCard,
        error: WFColors.error,
      ),
      scaffoldBackgroundColor: WFColors.bgPrimary,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: WFColors.bgPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: WFColors.textPrimary,
        ),
        iconTheme: IconThemeData(color: WFColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: WFColors.bgCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: WFColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WFColors.bgCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: WFColors.textLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: WFColors.textLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: WFColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        labelStyle: const TextStyle(color: WFColors.textSecondary),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: WFColors.bgCard,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: WFColors.textPrimary,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 14,
          color: WFColors.textSecondary,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentTextStyle: const TextStyle(fontSize: 14),
        backgroundColor: WFColors.primary,
        actionTextColor: WFColors.accentLight,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        backgroundColor: WFColors.bgCard,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Colors.black.withValues(alpha: 0.4),
      ),
    );
  }

  /// 构建深色主题 — 基于 WFColors 的深色变体
  static ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: null,
      colorScheme: ColorScheme.fromSeed(
        seedColor: WFColors.primary,
        brightness: Brightness.dark,
      ).copyWith(
        primary: WFColors.darkPrimary, // 深色模式下用浅色主色
        error: WFColors.error,
      ),
      scaffoldBackgroundColor: WFColors.bgDark,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        backgroundColor: WFColors.darkSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: WFColors.darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: WFColors.darkPrimary,
          foregroundColor: WFColors.bgDark,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WFColors.darkSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: WFColors.darkPrimary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        labelStyle: const TextStyle(color: Colors.white70),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: WFColors.darkSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        contentTextStyle: const TextStyle(
          fontSize: 14,
          color: Colors.white70,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentTextStyle: const TextStyle(fontSize: 14),
        backgroundColor: WFColors.darkSurface,
        actionTextColor: WFColors.accentLight,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        backgroundColor: WFColors.darkSurface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Colors.black.withValues(alpha: 0.6),
      ),
    );
  }

  /// 构建高对比度主题覆盖（无障碍支持）
  ThemeData _buildHighContrastOverlay(ThemeData base) {
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: base.brightness == Brightness.dark ? Colors.white : Colors.black,
        onPrimary: base.brightness == Brightness.dark ? Colors.black : Colors.white,
        surface: base.brightness == Brightness.dark ? Colors.black : Colors.white,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: base.brightness == Brightness.dark ? Colors.black : Colors.white,
        foregroundColor: base.brightness == Brightness.dark ? Colors.white : Colors.black,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: base.brightness == Brightness.dark ? Colors.white : Colors.black,
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: base.brightness == Brightness.dark ? Colors.white : Colors.black,
        displayColor: base.brightness == Brightness.dark ? Colors.white : Colors.black,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 决定首页显示什么
    Widget homeWidget;
    if (!_onboardingChecked) {
      homeWidget = const Scaffold(body: Center(child: CircularProgressIndicator()));
    } else if (!_onboardingSeen) {
      homeWidget = const OnboardingScreen();
    } else {
      homeWidget = _useBottomNav 
        ? MainNavigationPage(onThemeChanged: () => _loadThemeMode())
        : HomeScreen(onThemeChanged: () => _loadThemeMode());
    }

    return MaterialApp(
      title: '手迹造字 WriteFont',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh'),
        Locale('en'),
        Locale('ja'),
        Locale('ko'),
        Locale('fr'),
        Locale('de'),
        Locale('es'),
      ],
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: _themeMode,
      // ── 无障碍：键盘快捷键支持 ──
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.keyH, control: true):
            const _ToggleHighContrastIntent(),
        const SingleActivator(LogicalKeyboardKey.equal, control: true):
            const _IncreaseFontIntent(),
        const SingleActivator(LogicalKeyboardKey.minus, control: true):
            const _DecreaseFontIntent(),
      },
      actions: {
        ...WidgetsApp.defaultActions,
        _ToggleHighContrastIntent: CallbackAction<_ToggleHighContrastIntent>(
          onInvoke: (_) => _toggleHighContrast(),
        ),
        _IncreaseFontIntent: CallbackAction<_IncreaseFontIntent>(
          onInvoke: (_) => _adjustAccessibilityFont(0.1),
        ),
        _DecreaseFontIntent: CallbackAction<_DecreaseFontIntent>(
          onInvoke: (_) => _adjustAccessibilityFont(-0.1),
        ),
      },
      // ── 无障碍：全局字体缩放 + 高对比度 + 减少动画 ──
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        final effectiveScale = mediaQuery.textScaler.scale(_accessibilityFontScale);
        Widget result = MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(effectiveScale),
            highContrast: _highContrastMode,
          ),
          child: child ?? const SizedBox.shrink(),
        );
        if (_highContrastMode) {
          result = Theme(
            data: _buildHighContrastOverlay(Theme.of(context)),
            child: result,
          );
        }
        return result;
      },
      home: homeWidget,
      onGenerateRoute: (settings) {
        // 分析：记录路由导航
        AppAnalytics.trackPageView(settings.name ?? 'unknown');
        switch (settings.name) {
          case '/writing-tips':
            return WFAnimations.slideRoute(const WritingTipsScreen());
          case '/charset-guide':
            return WFAnimations.slideRoute(const CharsetGuideScreen());
          case '/ocr-settings':
            return WFAnimations.scaleFadeRoute(const OcrSettingsScreen());
          case '/my-fonts':
            return WFAnimations.slideRoute(const ProjectListScreen());
          case '/settings':
            return WFAnimations.slideRoute(SettingsScreen(onThemeChanged: () => _loadThemeMode()));
          case '/ai-font-generator':
            return WFAnimations.slideUpRoute(const AiFontGeneratorScreen());
          case '/auto-generate':
            final imageBytes = (settings.arguments as Map<String, dynamic>?)?['imageBytes'] as Uint8List?;
            if (imageBytes != null) {
              return WFAnimations.slideUpRoute(AutoGenerateScreen(imageBytes: imageBytes));
            }
            return WFAnimations.fadeRoute(HomeScreen(onThemeChanged: () => _loadThemeMode()));
          case '/capture':
            final charset = (settings.arguments as Map<String, dynamic>?)?['charset'] as List<String>?;
            return WFAnimations.slideUpRoute(CaptureScreen(charset: charset));
          case '/processing':
            final args = settings.arguments as Map<String, dynamic>?;
            if (args == null) return WFAnimations.fadeRoute(HomeScreen(onThemeChanged: () => _loadThemeMode()));
            final images = args['images'] as List<Uint8List>?;
            if (images == null || images.isEmpty) return WFAnimations.fadeRoute(HomeScreen(onThemeChanged: () => _loadThemeMode()));
            final charset = args['charset'] as List<String>?;
            return WFAnimations.slideUpRoute(ProcessingScreen(sourceImages: images, charset: charset));
          case '/preview':
            final args = settings.arguments as Map<String, dynamic>?;
            final project = args?['project'] as FontProject?;
            if (project == null) return WFAnimations.fadeRoute(HomeScreen(onThemeChanged: () => _loadThemeMode()));
            return WFAnimations.scaleFadeRoute(PreviewScreen(project: project));
          default:
            return WFAnimations.fadeRoute(HomeScreen(onThemeChanged: () => _loadThemeMode()));
        }
      },
    );
  }
}
