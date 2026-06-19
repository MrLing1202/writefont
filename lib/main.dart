import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;
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
import 'services/storage_service.dart';
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
/// - 报告生成（项目报告、使用报告、性能报告、错误报告）
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

  // ═══════════════════════════════════════════════════════════
  // 报告生成功能：项目报告、使用报告、性能报告、错误报告
  // ═══════════════════════════════════════════════════════════

  /// 生成项目报告
  ///
  /// 包含项目概览、字符统计、进度分布等信息
  /// [projects] 项目列表
  /// 返回格式化的报告文本
  String generateProjectReport(List<dynamic> projects) {
    try {
      final buffer = StringBuffer();
      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln('        WriteFont 项目报告');
      buffer.writeln('        生成时间: ${DateTime.now().toLocal()}');
      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln();

      // 项目概览
      buffer.writeln('【项目概览】');
      buffer.writeln('  总项目数: ${projects.length}');

      int totalGlyphs = 0;
      int totalEdited = 0;
      int completedCount = 0;
      int inProgressCount = 0;
      int emptyCount = 0;

      for (final project in projects) {
        final glyphCount = project.glyphs.length;
        final editedCount = project.glyphs.values
            .where((g) => g.contours.isNotEmpty)
            .length;
        totalGlyphs += glyphCount;
        totalEdited += editedCount;

        if (glyphCount == 0 || editedCount == 0) {
          emptyCount++;
        } else if (editedCount >= glyphCount * 0.8) {
          completedCount++;
        } else {
          inProgressCount++;
        }
      }

      buffer.writeln('  总字符数: $totalGlyphs');
      buffer.writeln('  已编辑字符: $totalEdited');
      buffer.writeln('  完成率: ${totalGlyphs > 0 ? (totalEdited / totalGlyphs * 100).toStringAsFixed(1) : 0}%');
      buffer.writeln();

      // 进度分布
      buffer.writeln('【进度分布】');
      buffer.writeln('  已完成: $completedCount 个项目');
      buffer.writeln('  进行中: $inProgressCount 个项目');
      buffer.writeln('  未开始: $emptyCount 个项目');
      buffer.writeln();

      // 各项目详情
      buffer.writeln('【项目详情】');
      for (int i = 0; i < projects.length; i++) {
        final project = projects[i];
        final glyphCount = project.glyphs.length;
        final editedCount = project.glyphs.values
            .where((g) => g.contours.isNotEmpty)
            .length;
        final progress = glyphCount > 0 ? (editedCount / glyphCount * 100).toStringAsFixed(1) : '0.0';
        buffer.writeln('  ${i + 1}. ${project.name}');
        buffer.writeln('     字符数: $glyphCount | 已编辑: $editedCount | 进度: $progress%');
        buffer.writeln('     创建: ${project.createdAt.toLocal()}');
        buffer.writeln('     更新: ${project.updatedAt.toLocal()}');
      }

      buffer.writeln();
      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln('              报告结束');
      buffer.writeln('═══════════════════════════════════════');

      debugPrint('[CategoryService] 项目报告生成完成: ${projects.length} 个项目');
      return buffer.toString();
    } catch (e) {
      debugPrint('[CategoryService] 生成项目报告失败: $e');
      return '报告生成失败: $e';
    }
  }

  /// 生成使用报告
  ///
  /// 包含功能使用频率、页面访问统计等信息
  /// 返回格式化的报告文本
  String generateUsageReport() {
    try {
      final buffer = StringBuffer();
      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln('        WriteFont 使用报告');
      buffer.writeln('        生成时间: ${DateTime.now().toLocal()}');
      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln();

      // 获取分析数据
      final analyticsReport = AppAnalytics.getUsageReport();

      buffer.writeln('【功能使用统计】');
      final featureUsage = analyticsReport['featureUsage'] as Map<String, dynamic>? ?? {};
      if (featureUsage.isEmpty) {
        buffer.writeln('  暂无功能使用数据');
      } else {
        final sortedFeatures = featureUsage.entries.toList()
          ..sort((a, b) => (b.value as int).compareTo(a.value as int));
        for (final entry in sortedFeatures.take(10)) {
          buffer.writeln('  ${entry.key}: ${entry.value} 次');
        }
      }
      buffer.writeln();

      buffer.writeln('【页面访问统计】');
      final pageViews = analyticsReport['pageViews'] as Map<String, dynamic>? ?? {};
      if (pageViews.isEmpty) {
        buffer.writeln('  暂无页面访问数据');
      } else {
        final sortedPages = pageViews.entries.toList()
          ..sort((a, b) => (b.value as int).compareTo(a.value as int));
        for (final entry in sortedPages.take(10)) {
          buffer.writeln('  ${entry.key}: ${entry.value} 次');
        }
      }
      buffer.writeln();

      buffer.writeln('【会话信息】');
      buffer.writeln('  会话次数: ${analyticsReport['sessionCount'] ?? 0}');
      buffer.writeln('  当前页面: ${analyticsReport['currentPage'] ?? '未知'}');

      buffer.writeln();
      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln('              报告结束');
      buffer.writeln('═══════════════════════════════════════');

      debugPrint('[CategoryService] 使用报告生成完成');
      return buffer.toString();
    } catch (e) {
      debugPrint('[CategoryService] 生成使用报告失败: $e');
      return '报告生成失败: $e';
    }
  }

  /// 生成性能报告
  ///
  /// 包含应用启动时间、页面切换延迟、存储性能等信息
  /// 返回格式化的报告文本
  String generatePerformanceReport() {
    try {
      final buffer = StringBuffer();
      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln('        WriteFont 性能报告');
      buffer.writeln('        生成时间: ${DateTime.now().toLocal()}');
      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln();

      // 应用运行时间
      final analyticsReport = AppAnalytics.getUsageReport();
      final uptimeMinutes = analyticsReport['uptimeMinutes'] as double? ?? 0.0;

      buffer.writeln('【应用运行信息】');
      buffer.writeln('  运行时长: ${uptimeMinutes.toStringAsFixed(1)} 分钟');
      buffer.writeln('  会话次数: ${analyticsReport['sessionCount'] ?? 0}');
      buffer.writeln();

      // 性能事件统计
      final perfEvents = analyticsReport['performanceEvents'] as List<dynamic>? ?? [];
      buffer.writeln('【性能事件统计】');
      buffer.writeln('  记录事件数: ${perfEvents.length}');
      if (perfEvents.isNotEmpty) {
        final recentEvents = perfEvents.take(5);
        buffer.writeln('  最近事件:');
        for (final event in recentEvents) {
          final eventMap = event as Map<String, dynamic>;
          buffer.writeln('    - ${eventMap['event']}: ${eventMap['durationMs']?.toStringAsFixed(1) ?? 'N/A'} ms');
        }
      }
      buffer.writeln();

      // 存储性能指标
      buffer.writeln('【存储性能指标】');
      final metrics = StorageService.getPerformanceMetrics();
      buffer.writeln('  记录操作数: ${metrics.length}');
      if (metrics.isNotEmpty) {
        final avgDuration = metrics.fold(0.0, (sum, m) => sum + (m['elapsedMs'] as double? ?? 0.0)) / metrics.length;
        buffer.writeln('  平均操作耗时: ${avgDuration.toStringAsFixed(2)} ms');
      }

      buffer.writeln();
      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln('              报告结束');
      buffer.writeln('═══════════════════════════════════════');

      debugPrint('[CategoryService] 性能报告生成完成');
      return buffer.toString();
    } catch (e) {
      debugPrint('[CategoryService] 生成性能报告失败: $e');
      return '报告生成失败: $e';
    }
  }

  /// 生成错误报告
  ///
  /// 包含错误事件统计、最近错误详情等信息
  /// 返回格式化的报告文本
  String generateErrorReport() {
    try {
      final buffer = StringBuffer();
      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln('        WriteFont 错误报告');
      buffer.writeln('        生成时间: ${DateTime.now().toLocal()}');
      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln();

      final analyticsReport = AppAnalytics.getUsageReport();
      final errorEvents = analyticsReport['errorEvents'] as List<dynamic>? ?? [];

      buffer.writeln('【错误统计】');
      buffer.writeln('  错误总数: ${errorEvents.length}');
      buffer.writeln();

      if (errorEvents.isNotEmpty) {
        buffer.writeln('【最近错误详情】');
        final recentErrors = errorEvents.take(10);
        int index = 1;
        for (final error in recentErrors) {
          final errorMap = error as Map<String, dynamic>;
          buffer.writeln('  $index. ${errorMap['error'] ?? '未知错误'}');
          buffer.writeln('     时间: ${errorMap['timestamp'] ?? 'N/A'}');
          buffer.writeln('     上下文: ${errorMap['context'] ?? '无'}');
          buffer.writeln();
          index++;
        }
      } else {
        buffer.writeln('  无错误记录 ✓');
      }

      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln('              报告结束');
      buffer.writeln('═══════════════════════════════════════');

      debugPrint('[CategoryService] 错误报告生成完成: ${errorEvents.length} 个错误');
      return buffer.toString();
    } catch (e) {
      debugPrint('[CategoryService] 生成错误报告失败: $e');
      return '报告生成失败: $e';
    }
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

  // ═══════════════════════════════════════════════════════════
  // 存储空间管理：统计、清理建议、优化建议、报告生成
  // ═══════════════════════════════════════════════════════════

  /// 获取空间使用统计
  ///
  /// 聚合存储服务和识别服务的空间使用数据
  static Future<Map<String, dynamic>> getStorageSpaceUsage() async {
    try {
      final storageUsage = await StorageService.getStorageUsage();
      final cacheUsage = RecognitionService.getCacheSpaceUsage();

      return {
        'storage': storageUsage,
        'cache': cacheUsage,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      debugPrint('[Analytics] 获取空间使用统计失败: $e');
      return {
        'storage': <String, dynamic>{},
        'cache': <String, dynamic>{},
        'error': e.toString(),
      };
    }
  }

  /// 获取空间清理建议
  ///
  /// 综合存储和缓存的清理建议
  static Future<List<Map<String, dynamic>>> getStorageCleanupSuggestions() async {
    final suggestions = <Map<String, dynamic>>[];

    try {
      // 存储清理建议
      final storageSuggestions = await StorageService.getStorageSuggestions();
      suggestions.addAll(storageSuggestions);

      // 缓存清理建议
      final cacheSuggestions = RecognitionService.getCacheCleanupSuggestions();
      suggestions.addAll(cacheSuggestions);

      // 按优先级排序：high > medium > low > none
      const priorityOrder = {'high': 0, 'medium': 1, 'low': 2, 'none': 3};
      suggestions.sort((a, b) {
        final aPriority = priorityOrder[a['priority']] ?? 3;
        final bPriority = priorityOrder[b['priority']] ?? 3;
        return aPriority.compareTo(bPriority);
      });
    } catch (e) {
      debugPrint('[Analytics] 获取清理建议失败: $e');
    }

    return suggestions;
  }

  /// 获取空间优化建议
  ///
  /// 基于使用模式和存储状态生成优化建议
  static Future<List<Map<String, dynamic>>> getStorageOptimizationSuggestions() async {
    final suggestions = <Map<String, dynamic>>[];

    try {
      final usage = await StorageService.getStorageUsage();
      final totalBytes = (usage['total'] as Map<String, dynamic>?)?['bytes'] as int? ?? 0;
      final projectBytes = ((usage['projects'] as Map<String, dynamic>?)?['bytes'] as int?) ?? 0;
      final backupBytes = ((usage['backups'] as Map<String, dynamic>?)?['bytes'] as int?) ?? 0;

      // 项目数据占比过高
      if (totalBytes > 0 && projectBytes > totalBytes * 0.7) {
        suggestions.add({
          'type': 'project_dominant',
          'title': '项目数据占比过高',
          'description': '项目数据占用 ${StorageService.formatBytes(projectBytes)}，'
              '占总存储的 ${(projectBytes / totalBytes * 100).toStringAsFixed(0)}%',
          'recommendation': '考虑导出不需要的项目后删除，释放空间',
          'priority': 'medium',
        });
      }

      // 备份数据过大
      if (backupBytes > 50 * 1024 * 1024) {
        suggestions.add({
          'type': 'backup_large',
          'title': '备份数据较大',
          'description': '备份占用 ${StorageService.formatBytes(backupBytes)}',
          'recommendation': '减少每个项目的备份数量，保留最近 3-5 个版本即可',
          'priority': 'medium',
        });
      }

      // 缓存优化建议
      final cacheUsage = RecognitionService.getCacheSpaceUsage();
      final cachePercent = cacheUsage['cacheUsagePercent'] as double? ?? 0;
      if (cachePercent > 50) {
        suggestions.add({
          'type': 'cache_optimization',
          'title': '识别缓存可优化',
          'description': '缓存使用率 ${cachePercent.toStringAsFixed(0)}%',
          'recommendation': '定期清理低置信度的缓存条目，提升缓存效率',
          'priority': 'low',
        });
      }

      // 图片压缩建议
      final projects = await StorageService.loadProjects();
      int totalSourceImages = 0;
      for (final p in projects) {
        totalSourceImages += p.sourceImages.length;
      }
      if (totalSourceImages > 50) {
        suggestions.add({
          'type': 'image_compression',
          'title': '源图片较多',
          'description': '共有 $totalSourceImages 张源图片',
          'recommendation': '考虑使用 ImageProcessor.compressImage 压缩源图片，减少存储占用',
          'priority': 'low',
        });
      }

      if (suggestions.isEmpty) {
        suggestions.add({
          'type': 'no_action',
          'title': '存储状态良好',
          'description': '当前存储使用合理，无需优化',
          'recommendation': '继续保持良好的使用习惯',
          'priority': 'none',
        });
      }
    } catch (e) {
      debugPrint('[Analytics] 获取优化建议失败: $e');
    }

    return suggestions;
  }

  /// 生成空间报告
  ///
  /// 包含完整的空间使用详情、清理建议、优化建议、缓存状态
  static Future<Map<String, dynamic>> generateStorageReport() async {
    final report = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'appVersion': 'v2.16.0',
    };

    try {
      // 空间使用统计
      report['spaceUsage'] = await getStorageSpaceUsage();

      // 清理建议
      report['cleanupSuggestions'] = await getStorageCleanupSuggestions();

      // 优化建议
      report['optimizationSuggestions'] = await getStorageOptimizationSuggestions();

      // 缓存空间报告
      report['cacheReport'] = await RecognitionService.getCacheSpaceReport();

      // 存储空间报告
      report['storageReport'] = await StorageService.getStorageReport();

      // 应用运行信息
      report['sessionInfo'] = getSessionInfo();

      // 使用统计
      report['usageReport'] = getUsageReport();
    } catch (e) {
      debugPrint('[Analytics] 生成存储报告失败: $e');
      report['error'] = e.toString();
    }

    return report;
  }

  /// 执行空间清理
  ///
  /// 综合清理临时文件、优化缓存、清理旧导出等
  /// 返回清理报告
  static Future<Map<String, dynamic>> performSpaceCleanup() async {
    final cleanupReport = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      // 1. 清理存储空间
      final freedBytes = await StorageService.cleanupStorage();
      cleanupReport['storageCleanup'] = {
        'freedBytes': freedBytes,
        'freedFormatted': StorageService.formatBytes(freedBytes),
      };

      // 2. 优化识别缓存
      final optimizedCount = RecognitionService.optimizeCache();
      cleanupReport['cacheOptimization'] = {
        'removedEntries': optimizedCount,
      };

      // 3. 优化存储（清理孤立目录）
      final optimizeResult = await StorageService.optimizeStorage();
      cleanupReport['storageOptimization'] = optimizeResult;

      cleanupReport['success'] = true;
    } catch (e) {
      debugPrint('[Analytics] 执行空间清理失败: $e');
      cleanupReport['success'] = false;
      cleanupReport['error'] = e.toString();
    }

    return cleanupReport;
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
    _metricCollectors.clear();
  }

  /// 辅助方法：获取 Map 中值最大的 key
  static String? _getMaxKey(Map<String, int> map) {
    if (map.isEmpty) return null;
    return map.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  // ═══════════════════════════════════════════════════════════
  // 数据分析优化：数据收集、数据处理、数据可视化、数据报告
  // ═══════════════════════════════════════════════════════════

  /// 数据收集器：按类别收集结构化数据点
  ///
  /// 支持按类别分组收集，自动去重和时间戳记录
  static final Map<String, List<Map<String, dynamic>>> _dataCollections = {};
  static const int _maxDataPointsPerCategory = 500;

  /// 收集数据点
  ///
  /// [category] 数据类别（如 'user_action', 'system_metric', 'feature_usage'）
  /// [dataPoint] 数据点 Map，包含具体数据字段
  static void collectData(String category, Map<String, dynamic> dataPoint) {
    try {
      _dataCollections.putIfAbsent(category, () => []);
      final collection = _dataCollections[category]!;
      collection.add({
        ...dataPoint,
        '_collectedAt': DateTime.now().toIso8601String(),
      });
      // 限制每个类别的数据点数量
      if (collection.length > _maxDataPointsPerCategory) {
        collection.removeRange(0, collection.length - _maxDataPointsPerCategory);
      }
      debugPrint('[Analytics] 数据收集: $category (共${collection.length}条)');
    } catch (e) {
      debugPrint('[Analytics] 数据收集失败: $e');
    }
  }

  /// 获取指定类别的数据集合
  static List<Map<String, dynamic>> getCollectedData(String category) {
    return List.unmodifiable(_dataCollections[category] ?? []);
  }

  /// 获取所有数据类别
  static List<String> getDataCategories() {
    return _dataCollections.keys.toList();
  }

  /// 数据处理：聚合分析收集的数据
  ///
  /// [category] 数据类别
  /// [aggregationField] 聚合字段名
  /// [operation] 聚合操作（'count', 'sum', 'avg', 'min', 'max'）
  /// 返回聚合结果
  static Map<String, dynamic> processData(String category,
      {String? aggregationField, String operation = 'count'}) {
    try {
      final data = _dataCollections[category] ?? [];
      if (data.isEmpty) {
        return {'category': category, 'count': 0, 'result': null};
      }

      final result = <String, dynamic>{
        'category': category,
        'count': data.length,
        'operation': operation,
      };

      if (aggregationField != null) {
        final values = data
            .where((d) => d.containsKey(aggregationField))
            .map((d) => d[aggregationField])
            .toList();

        if (values.isNotEmpty) {
          final numericValues = values
              .where((v) => v is num)
              .map((v) => (v as num).toDouble())
              .toList();

          if (numericValues.isNotEmpty) {
            switch (operation) {
              case 'sum':
                result['result'] = numericValues.reduce((a, b) => a + b);
                break;
              case 'avg':
                result['result'] = numericValues.reduce((a, b) => a + b) / numericValues.length;
                break;
              case 'min':
                result['result'] = numericValues.reduce((a, b) => a < b ? a : b);
                break;
              case 'max':
                result['result'] = numericValues.reduce((a, b) => a > b ? a : b);
                break;
              default: // count
                result['result'] = numericValues.length;
            }
          }
        }
      }

      // 时间分布统计
      final timeDistribution = <String, int>{};
      for (final d in data) {
        final timestamp = d['_collectedAt'] as String?;
        if (timestamp != null) {
          final date = DateTime.tryParse(timestamp);
          if (date != null) {
            final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            timeDistribution[dateKey] = (timeDistribution[dateKey] ?? 0) + 1;
          }
        }
      }
      result['timeDistribution'] = timeDistribution;

      return result;
    } catch (e) {
      debugPrint('[Analytics] 数据处理失败: $e');
      return {'category': category, 'error': e.toString()};
    }
  }

  /// 数据可视化：生成数据可视化报告
  ///
  /// 返回适合在 UI 中展示的结构化可视化数据
  /// 包含图表数据、趋势数据、分布数据
  static Map<String, dynamic> generateVisualizationData() {
    try {
      final visualization = <String, dynamic>{
        'generatedAt': DateTime.now().toIso8601String(),
        'categories': <String, dynamic>{},
        'trends': <String, dynamic>{},
        'distributions': <String, dynamic>{},
      };

      // 为每个数据类别生成可视化数据
      for (final entry in _dataCollections.entries) {
        final category = entry.key;
        final data = entry.value;

        if (data.isEmpty) continue;

        // 类别概览
        (visualization['categories'] as Map<String, dynamic>)[category] = {
          'count': data.length,
          'firstRecord': data.first['_collectedAt'],
          'lastRecord': data.last['_collectedAt'],
        };

        // 时间趋势数据（按小时聚合）
        final hourlyTrend = <String, int>{};
        for (final d in data) {
          final timestamp = d['_collectedAt'] as String?;
          if (timestamp != null) {
            final date = DateTime.tryParse(timestamp);
            if (date != null) {
              final hourKey = '${date.hour.toString().padLeft(2, '0')}:00';
              hourlyTrend[hourKey] = (hourlyTrend[hourKey] ?? 0) + 1;
            }
          }
        }
        (visualization['trends'] as Map<String, dynamic>)[category] = hourlyTrend;

        // 字段分布统计
        final fieldDistribution = <String, Map<String, int>>{};
        for (final d in data) {
          for (final field in d.keys) {
            if (field.startsWith('_')) continue; // 跳过内部字段
            fieldDistribution.putIfAbsent(field, () => {});
            final value = d[field]?.toString() ?? 'null';
            fieldDistribution[field]![value] = (fieldDistribution[field]![value] ?? 0) + 1;
          }
        }
        (visualization['distributions'] as Map<String, dynamic>)[category] = fieldDistribution;
      }

      return visualization;
    } catch (e) {
      debugPrint('[Analytics] 生成可视化数据失败: $e');
      return {'error': e.toString()};
    }
  }

  /// 数据报告：生成综合数据分析报告
  ///
  /// 包含数据概览、各类别统计、趋势分析、异常检测
  /// 返回格式化的报告文本
  static String generateDataReport() {
    try {
      final buffer = StringBuffer();
      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln('        WriteFont 数据分析报告');
      buffer.writeln('        生成时间: ${DateTime.now().toLocal()}');
      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln();

      // 数据概览
      buffer.writeln('【数据概览】');
      int totalDataPoints = 0;
      for (final data in _dataCollections.values) {
        totalDataPoints += data.length;
      }
      buffer.writeln('  数据类别数: ${_dataCollections.length}');
      buffer.writeln('  总数据点数: $totalDataPoints');
      buffer.writeln();

      // 各类别详情
      if (_dataCollections.isNotEmpty) {
        buffer.writeln('【类别统计】');
        for (final entry in _dataCollections.entries) {
          final stats = processData(entry.key);
          buffer.writeln('  ${entry.key}:');
          buffer.writeln('    数据量: ${stats['count']}');
          if (stats['timeDistribution'] != null) {
            final dist = stats['timeDistribution'] as Map<String, int>;
            if (dist.isNotEmpty) {
              buffer.writeln('    活跃天数: ${dist.length}');
              final mostActiveDay = dist.entries.reduce((a, b) => a.value > b.value ? a : b);
              buffer.writeln('    最活跃日: ${mostActiveDay.key} (${mostActiveDay.value}条)');
            }
          }
        }
        buffer.writeln();
      }

      // 使用分析摘要
      buffer.writeln('【使用分析摘要】');
      buffer.writeln('  总页面访问: ${_pageViews.values.fold(0, (a, b) => a + b)}');
      buffer.writeln('  总功能使用: ${_featureUsage.values.fold(0, (a, b) => a + b)}');
      buffer.writeln('  性能事件数: ${_performanceEvents.length}');
      buffer.writeln('  错误事件数: ${_errorEvents.length}');
      buffer.writeln();

      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln('              报告结束');
      buffer.writeln('═══════════════════════════════════════');

      return buffer.toString();
    } catch (e) {
      debugPrint('[Analytics] 生成数据报告失败: $e');
      return '数据报告生成失败: $e';
    }
  }

  /// 清除指定类别的数据
  static void clearDataCategory(String category) {
    _dataCollections.remove(category);
  }

  /// 清除所有收集的数据
  static void clearAllData() {
    _dataCollections.clear();
  }

  // ═══════════════════════════════════════════════════════════
  // 性能监控优化：指标收集、报警、报告生成、优化建议
  // ═══════════════════════════════════════════════════════════

  /// 性能指标收集器
  ///
  /// 收集各类操作的性能指标（耗时、内存、频率等），
  /// 用于性能报警和报告生成。
  static final Map<String, _PerformanceMetricCollector> _metricCollectors = {};

  /// 性能报警阈值配置
  static final Map<String, double> _performanceThresholds = {
    'page_transition': 500.0,    // 页面切换超过 500ms 报警
    'saveProject': 2000.0,       // 保存项目超过 2s 报警
    'loadProjects': 3000.0,      // 加载项目列表超过 3s 报警
    'recognition': 5000.0,       // 字符识别超过 5s 报警
  };

  /// 性能报警回调列表
  static final List<void Function(String metric, double value, double threshold)> _alertCallbacks = [];

  /// 记录性能指标（增强版，含指标收集和报警检测）
  ///
  /// [metricName] 指标名称
  /// [value] 指标值
  /// [unit] 单位（默认 'ms'）
  /// [metadata] 附加元数据
  static void recordMetric(String metricName, double value,
      {String unit = 'ms', Map<String, dynamic>? metadata}) {
    // 收集指标
    _metricCollectors.putIfAbsent(metricName, () => _PerformanceMetricCollector(metricName));
    _metricCollectors[metricName]!.add(value);

    // 同时记录到性能事件
    trackPerformance(metricName, duration: Duration(microseconds: (value * 1000).toInt()), metadata: metadata);

    // 检查是否触发报警
    final threshold = _performanceThresholds[metricName];
    if (threshold != null && value > threshold) {
      _triggerPerformanceAlert(metricName, value, threshold);
    }
  }

  /// 触发性能报警
  static void _triggerPerformanceAlert(String metric, double value, double threshold) {
    debugPrint('[Analytics] ⚠️ 性能报警: $metric = ${value.toStringAsFixed(1)}ms (阈值: ${threshold.toStringAsFixed(1)}ms)');
    for (final callback in _alertCallbacks) {
      try {
        callback(metric, value, threshold);
      } catch (_) {}
    }
  }

  /// 添加性能报警回调
  static void addPerformanceAlertCallback(
      void Function(String metric, double value, double threshold) callback) {
    _alertCallbacks.add(callback);
  }

  /// 移除性能报警回调
  static void removePerformanceAlertCallback(
      void Function(String metric, double value, double threshold) callback) {
    _alertCallbacks.remove(callback);
  }

  /// 设置性能报警阈值
  ///
  /// [metricName] 指标名称
  /// [thresholdMs] 阈值（毫秒）
  static void setPerformanceThreshold(String metricName, double thresholdMs) {
    _performanceThresholds[metricName] = thresholdMs;
  }

  /// 生成性能报告（增强版）
  ///
  /// 返回包含以下信息的完整性能报告：
  /// - 各指标的统计数据（平均值、中位数、P95、P99、最大值）
  /// - 性能报警历史
  /// - 性能优化建议
  /// - 资源使用情况
  static Map<String, dynamic> generatePerformanceReport() {
    final metricsReport = <String, dynamic>{};
    for (final entry in _metricCollectors.entries) {
      metricsReport[entry.key] = entry.value.getStats();
    }

    return {
      'reportTime': DateTime.now().toIso8601String(),
      'uptime': uptime?.inSeconds ?? 0,
      'sessionCount': _sessionCount,
      'metrics': metricsReport,
      'thresholds': Map<String, double>.from(_performanceThresholds),
      'optimizationSuggestions': getPerformanceOptimizationSuggestions(),
      'recentPerformanceEvents': _performanceEvents.take(50).toList(),
    };
  }

  /// 获取性能优化建议
  ///
  /// 根据当前性能数据自动分析并生成优化建议。
  /// 返回建议列表，每条包含建议类型、描述和优先级。
  static List<Map<String, dynamic>> getPerformanceOptimizationSuggestions() {
    final suggestions = <Map<String, dynamic>>[];

    // 检查页面切换性能
    final pageTransitionCollector = _metricCollectors['page_transition'];
    if (pageTransitionCollector != null) {
      final stats = pageTransitionCollector.getStats();
      final avgMs = stats['avg'] as double? ?? 0;
      if (avgMs > 300) {
        suggestions.add({
          'type': 'page_transition',
          'priority': 'high',
          'description': '页面切换平均耗时 ${avgMs.toStringAsFixed(0)}ms，建议优化页面懒加载或减少首屏渲染复杂度',
        });
      }
    }

    // 检查保存性能
    final saveCollector = _metricCollectors['saveProject'];
    if (saveCollector != null) {
      final stats = saveCollector.getStats();
      final avgMs = stats['avg'] as double? ?? 0;
      if (avgMs > 1000) {
        suggestions.add({
          'type': 'save_performance',
          'priority': 'medium',
          'description': '项目保存平均耗时 ${avgMs.toStringAsFixed(0)}ms，建议减少序列化数据量或异步保存',
        });
      }
    }

    // 检查加载性能
    final loadCollector = _metricCollectors['loadProjects'];
    if (loadCollector != null) {
      final stats = loadCollector.getStats();
      final avgMs = stats['avg'] as double? ?? 0;
      if (avgMs > 2000) {
        suggestions.add({
          'type': 'load_performance',
          'priority': 'high',
          'description': '项目列表加载平均耗时 ${avgMs.toStringAsFixed(0)}ms，建议启用增量加载或优化缓存策略',
        });
      }
    }

    // 检查识别性能
    final recognitionCollector = _metricCollectors['recognition'];
    if (recognitionCollector != null) {
      final stats = recognitionCollector.getStats();
      final avgMs = stats['avg'] as double? ?? 0;
      if (avgMs > 3000) {
        suggestions.add({
          'type': 'recognition_performance',
          'priority': 'medium',
          'description': '字符识别平均耗时 ${avgMs.toStringAsFixed(0)}ms，建议使用云端识别或减少预处理步骤',
        });
      }
    }

    // 检查错误率
    if (_errorEvents.isNotEmpty) {
      final recentErrors = _errorEvents.where((e) {
        final ts = DateTime.tryParse(e['timestamp'] as String? ?? '');
        if (ts == null) return false;
        return DateTime.now().difference(ts).inHours < 24;
      }).length;
      if (recentErrors > 10) {
        suggestions.add({
          'type': 'error_rate',
          'priority': 'critical',
          'description': '过去24小时内发生 $recentErrors 次错误，建议检查错误日志并修复',
        });
      }
    }

    return suggestions;
  }

  /// 获取指定指标的统计信息
  static Map<String, dynamic>? getMetricStats(String metricName) {
    return _metricCollectors[metricName]?.getStats();
  }

  /// 获取所有已收集的指标名称列表
  static List<String> getCollectedMetricNames() {
    return _metricCollectors.keys.toList();
  }

  /// 清除指定指标的收集数据
  static void clearMetricData(String metricName) {
    _metricCollectors.remove(metricName);
  }
}

/// 性能指标收集器
///
/// 统计单个性能指标的平均值、中位数、P95、P99、最大值等统计数据。
class _PerformanceMetricCollector {
  final String name;
  final List<double> _values = [];
  static const int _maxValues = 500;

  _PerformanceMetricCollector(this.name);

  /// 添加一个值
  void add(double value) {
    _values.add(value);
    if (_values.length > _maxValues) {
      _values.removeAt(0);
    }
  }

  /// 获取统计数据
  Map<String, dynamic> getStats() {
    if (_values.isEmpty) {
      return {
        'name': name,
        'count': 0,
        'avg': 0.0,
        'median': 0.0,
        'p95': 0.0,
        'p99': 0.0,
        'max': 0.0,
        'min': 0.0,
      };
    }

    final sorted = List<double>.from(_values)..sort();
    final sum = sorted.reduce((a, b) => a + b);
    final avg = sum / sorted.length;
    final median = sorted[sorted.length ~/ 2];
    final p95Index = (sorted.length * 0.95).round().clamp(0, sorted.length - 1);
    final p99Index = (sorted.length * 0.99).round().clamp(0, sorted.length - 1);

    return {
      'name': name,
      'count': sorted.length,
      'avg': avg,
      'median': median,
      'p95': sorted[p95Index],
      'p99': sorted[p99Index],
      'max': sorted.last,
      'min': sorted.first,
    };
  }
}

// ═══════════════════════════════════════════════════════════
// 兼容性服务：旧版本兼容、设备兼容、系统兼容、格式兼容
// ═══════════════════════════════════════════════════════════

/// 兼容性服务
///
/// 功能：
/// - 旧版本数据迁移与兼容
/// - 不同设备屏幕适配
/// - 不同系统版本兼容
/// - 不同文件格式兼容
class CompatibilityService {
  static final CompatibilityService _instance = CompatibilityService._();
  static CompatibilityService get instance => _instance;
  CompatibilityService._();

  /// 当前应用版本
  static const String currentVersion = 'v2.14.0';

  /// 支持的最低数据版本
  static const String minSupportedVersion = 'v1.0.0';

  /// SharedPreferences key
  static const String _keyAppVersion = 'app_version';
  static const String _keyMigrationVersion = 'data_migration_version';

  /// 初始化兼容性检查
  ///
  /// 在应用启动时调用，执行必要的数据迁移
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedVersion = prefs.getString(_keyAppVersion);

      if (savedVersion == null) {
        // 首次安装
        await prefs.setString(_keyAppVersion, currentVersion);
        debugPrint('[Compatibility] 首次安装，版本: $currentVersion');
      } else if (_isNewerVersion(currentVersion, savedVersion)) {
        // 版本升级
        debugPrint('[Compatibility] 版本升级: $savedVersion -> $currentVersion');
        await _performDataMigration(savedVersion, currentVersion);
        await prefs.setString(_keyAppVersion, currentVersion);
      }

      // 检查系统兼容性
      _checkSystemCompatibility();
    } catch (e) {
      debugPrint('[Compatibility] 兼容性初始化失败: $e');
    }
  }

  /// 比较版本号
  ///
  /// 返回 true 如果 v1 > v2
  bool _isNewerVersion(String v1, String v2) {
    final parts1 = v1.replaceAll('v', '').split('.').map(int.parse).toList();
    final parts2 = v2.replaceAll('v', '').split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 > p2) return true;
      if (p1 < p2) return false;
    }
    return false;
  }

  /// 执行数据迁移
  ///
  /// 处理不同版本之间的数据格式变化
  Future<void> _performDataMigration(String fromVersion, String toVersion) async {
    final prefs = await SharedPreferences.getInstance();
    final migrationVersion = prefs.getString(_keyMigrationVersion) ?? 'v0.0.0';

    // v2.0.0: 项目数据结构升级
    if (_isNewerVersion('v2.0.0', migrationVersion)) {
      debugPrint('[Compatibility] 执行 v2.0.0 数据迁移');
      await _migrateToV2();
      await prefs.setString(_keyMigrationVersion, 'v2.0.0');
    }

    // v2.10.0: 新增元数据字段
    if (_isNewerVersion('v2.10.0', migrationVersion)) {
      debugPrint('[Compatibility] 执行 v2.10.0 数据迁移');
      await _migrateToV210();
      await prefs.setString(_keyMigrationVersion, 'v2.10.0');
    }

    // v2.14.0: 当前版本迁移
    if (_isNewerVersion('v2.14.0', migrationVersion)) {
      debugPrint('[Compatibility] 执行 v2.14.0 数据迁移');
      await _migrateToV214();
      await prefs.setString(_keyMigrationVersion, 'v2.14.0');
    }
  }

  /// v2.0.0 数据迁移：项目结构升级
  Future<void> _migrateToV2() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 确保项目列表格式兼容
      final projectsJson = prefs.getString('projects');
      if (projectsJson != null) {
        // 解析并验证格式
        final data = jsonDecode(projectsJson);
        if (data is List) {
          // 格式正确，无需迁移
        } else if (data is Map) {
          // 旧格式：转换为列表
          final projects = (data as Map<String, dynamic>).values.toList();
          await prefs.setString('projects', jsonEncode(projects));
        }
      }
      debugPrint('[Compatibility] v2.0.0 迁移完成');
    } catch (e) {
      debugPrint('[Compatibility] v2.0.0 迁移失败: $e');
    }
  }

  /// v2.10.0 数据迁移：新增元数据字段
  Future<void> _migrateToV210() async {
    try {
      // 确保所有项目都有 updatedAt 字段
      final prefs = await SharedPreferences.getInstance();
      final projectsJson = prefs.getString('projects');
      if (projectsJson != null) {
        final data = jsonDecode(projectsJson) as List;
        bool modified = false;
        for (final project in data) {
          if (project is Map<String, dynamic>) {
            if (!project.containsKey('updatedAt')) {
              project['updatedAt'] = DateTime.now().toIso8601String();
              modified = true;
            }
          }
        }
        if (modified) {
          await prefs.setString('projects', jsonEncode(data));
        }
      }
      debugPrint('[Compatibility] v2.10.0 迁移完成');
    } catch (e) {
      debugPrint('[Compatibility] v2.10.0 迁移失败: $e');
    }
  }

  /// v2.14.0 数据迁移：协作功能兼容
  Future<void> _migrateToV214() async {
    try {
      // 初始化协作相关的存储 key
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey('cloud_collaborators')) {
        await prefs.setString('cloud_collaborators', '[]');
      }
      if (!prefs.containsKey('cloud_collab_history')) {
        await prefs.setString('cloud_collab_history', '[]');
      }
      if (!prefs.containsKey('cloud_share_links')) {
        await prefs.setString('cloud_share_links', '[]');
      }
      debugPrint('[Compatibility] v2.14.0 迁移完成');
    } catch (e) {
      debugPrint('[Compatibility] v2.14.0 迁移失败: $e');
    }
  }

  /// 检查系统兼容性
  void _checkSystemCompatibility() {
    try {
      final info = getDeviceInfo();
      debugPrint('[Compatibility] 设备信息: $info');

      // 检查系统版本
      if (Platform.isIOS) {
        final version = info['osVersion'] ?? '0.0';
        final majorVersion = double.tryParse(version.split('.').first) ?? 0;
        if (majorVersion < 12) {
          debugPrint('[Compatibility] 警告: iOS 版本过低 ($version)，部分功能可能不可用');
        }
      } else if (Platform.isAndroid) {
        final sdkInt = int.tryParse(info['sdkInt'] ?? '0') ?? 0;
        if (sdkInt < 21) {
          debugPrint('[Compatibility] 警告: Android SDK 过低 ($sdkInt)，部分功能可能不可用');
        }
      }
    } catch (e) {
      debugPrint('[Compatibility] 系统兼容性检查失败: $e');
    }
  }

  /// 获取设备信息
  ///
  /// 返回设备平台、系统版本等信息
  Map<String, String> getDeviceInfo() {
    final info = <String, String>{
      'platform': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
    };
    return info;
  }

  /// 检查设备是否为平板
  ///
  /// 基于屏幕尺寸和设备类型判断
  bool isTablet(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final shortestSide = mediaQuery.size.shortestSide;
    return shortestSide >= 600;
  }

  /// 检查设备是否为桌面
  bool isDesktop() {
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  /// 获取适配后的内边距
  ///
  /// 根据设备类型返回合适的内边距
  EdgeInsets getAdaptivePadding(BuildContext context) {
    if (isTablet(context)) {
      return const EdgeInsets.symmetric(horizontal: 32, vertical: 24);
    } else if (isDesktop()) {
      return const EdgeInsets.symmetric(horizontal: 48, vertical: 32);
    }
    return const EdgeInsets.symmetric(horizontal: 16, vertical: 16);
  }

  /// 获取适配后的字体大小
  ///
  /// 根据设备类型返回合适的字体大小
  double getAdaptiveFontSize(BuildContext context, double baseFontSize) {
    if (isTablet(context)) {
      return baseFontSize * 1.1;
    } else if (isDesktop()) {
      return baseFontSize * 1.0;
    }
    return baseFontSize;
  }

  /// 检查文件格式兼容性
  ///
  /// 验证导入文件是否为支持的格式
  bool isSupportedFileFormat(String fileName, List<int> bytes) {
    final extension = fileName.split('.').last.toLowerCase();

    switch (extension) {
      case 'json':
        // 检查是否为有效 JSON
        try {
          final str = String.fromCharCodes(bytes);
          jsonDecode(str);
          return true;
        } catch (_) {
          return false;
        }

      case 'ttf':
        // 检查 TTF 魔数
        if (bytes.length >= 4) {
          return (bytes[0] == 0x00 && bytes[1] == 0x01 && bytes[2] == 0x00 && bytes[3] == 0x00) ||
                 (String.fromCharCodes(bytes.take(4)) == 'true');
        }
        return false;

      case 'otf':
        // 检查 OTF 魔数
        if (bytes.length >= 4) {
          return String.fromCharCodes(bytes.take(4)) == 'OTTO';
        }
        return false;

      case 'woff':
        // 检查 WOFF 魔数
        if (bytes.length >= 4) {
          return String.fromCharCodes(bytes.take(4)) == 'wOFF';
        }
        return false;

      default:
        return false;
    }
  }

  /// 格式兼容性：将旧版本数据格式转换为当前版本
  ///
  /// 处理不同来源的数据格式差异
  Map<String, dynamic> normalizeProjectData(Map<String, dynamic> raw) {
    final result = Map<String, dynamic>.from(raw);

    // 确保必要字段存在
    result['id'] = result['id'] ?? DateTime.now().microsecondsSinceEpoch.toString();
    result['name'] = result['name'] ?? '未命名项目';
    result['createdAt'] = result['createdAt'] ?? DateTime.now().toIso8601String();
    result['updatedAt'] = result['updatedAt'] ?? DateTime.now().toIso8601String();
    result['glyphs'] = result['glyphs'] ?? {};
    result['params'] = result['params'] ?? {};

    // 处理旧版本字段名变化
    if (result.containsKey('characters') && !result.containsKey('glyphs')) {
      result['glyphs'] = result['characters'];
      result.remove('characters');
    }

    if (result.containsKey('settings') && !result.containsKey('params')) {
      result['params'] = result['settings'];
      result.remove('settings');
    }

    // 处理日期格式兼容
    for (final key in ['createdAt', 'updatedAt']) {
      final value = result[key];
      if (value is int) {
        // 旧版本可能使用时间戳
        result[key] = DateTime.fromMillisecondsSinceEpoch(value).toIso8601String();
      }
    }

    return result;
  }
}

// ═══════════════════════════════════════════════════════════
// 推荐功能优化：智能推荐、热门推荐、相关推荐、个性化推荐
// ═══════════════════════════════════════════════════════════

/// 推荐服务
///
/// 功能：
/// - 智能推荐：基于用户使用模式和项目状态推荐最佳操作
/// - 热门推荐：基于功能使用频率推荐最常用的功能
/// - 相关推荐：基于当前上下文推荐相关功能
/// - 个性化推荐：基于用户偏好和技能等级推荐
class RecommendationService {
  static final RecommendationService _instance = RecommendationService._();
  static RecommendationService get instance => _instance;
  RecommendationService._();

  static const String _usageHistoryKey = 'recommendation_usage_history';
  static const int _maxHistoryItems = 100;
  List<Map<String, dynamic>> _usageHistory = [];

  /// 初始化推荐服务
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_usageHistoryKey);
      if (json != null) {
        final list = jsonDecode(json) as List;
        _usageHistory = list.cast<Map<String, dynamic>>();
      }
      debugPrint('[Recommendation] 初始化完成，${_usageHistory.length} 条历史');
    } catch (e) {
      debugPrint('[Recommendation] 初始化失败: $e');
    }
  }

  /// 记录用户操作（用于智能推荐的数据积累）
  Future<void> trackAction(String action, {Map<String, dynamic>? metadata}) async {
    try {
      _usageHistory.add({
        'action': action,
        'timestamp': DateTime.now().toIso8601String(),
        if (metadata != null) ...metadata,
      });
      // 限制历史记录数量
      if (_usageHistory.length > _maxHistoryItems) {
        _usageHistory = _usageHistory.sublist(_usageHistory.length - _maxHistoryItems);
      }
      // 异步保存
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_usageHistoryKey, jsonEncode(_usageHistory));
    } catch (e) {
      debugPrint('[Recommendation] 记录操作失败: $e');
    }
  }

  /// 智能推荐：基于用户使用模式推荐最佳操作
  ///
  /// 分析最近的操作历史，推荐最可能需要的下一步操作
  List<Map<String, dynamic>> getSmartRecommendations({int limit = 3}) {
    try {
      final recommendations = <Map<String, dynamic>>[];
      final recentActions = _usageHistory.take(20).toList();

      // 统计操作频率
      final actionCounts = <String, int>{};
      for (final action in recentActions) {
        final key = action['action'] as String? ?? 'unknown';
        actionCounts[key] = (actionCounts[key] ?? 0) + 1;
      }

      // 推荐最频繁的操作
      final sortedActions = actionCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      for (final entry in sortedActions.take(limit)) {
        final actionInfo = _getActionInfo(entry.key);
        if (actionInfo != null) {
          recommendations.add({
            ...actionInfo,
            'score': entry.value,
            'reason': '基于您的使用习惯',
          });
        }
      }

      // 如果历史不足，补充默认推荐
      if (recommendations.length < limit) {
        final defaults = _getDefaultRecommendations(limit - recommendations.length);
        recommendations.addAll(defaults);
      }

      return recommendations;
    } catch (e) {
      debugPrint('[Recommendation] 智能推荐失败: $e');
      return _getDefaultRecommendations(limit);
    }
  }

  /// 热门推荐：基于全局使用频率推荐最常用的功能
  List<Map<String, dynamic>> getPopularRecommendations({int limit = 3}) {
    try {
      // 统计所有操作频率
      final actionCounts = <String, int>{};
      for (final action in _usageHistory) {
        final key = action['action'] as String? ?? 'unknown';
        actionCounts[key] = (actionCounts[key] ?? 0) + 1;
      }

      final sortedActions = actionCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final recommendations = <Map<String, dynamic>>[];
      for (final entry in sortedActions.take(limit)) {
        final actionInfo = _getActionInfo(entry.key);
        if (actionInfo != null) {
          recommendations.add({
            ...actionInfo,
            'score': entry.value,
            'reason': '最受欢迎的功能',
          });
        }
      }

      return recommendations;
    } catch (e) {
      debugPrint('[Recommendation] 热门推荐失败: $e');
      return [];
    }
  }

  /// 相关推荐：基于当前上下文推荐相关功能
  ///
  /// [currentAction] 当前正在执行的操作
  List<Map<String, dynamic>> getRelatedRecommendations(String currentAction, {int limit = 3}) {
    try {
      // 定义功能关联关系
      final relatedMap = <String, List<String>>{
        'capture': ['standard', 'quick', 'free'],
        'standard': ['capture', 'preview', 'export'],
        'quick': ['capture', 'preview', 'ai'],
        'free': ['capture', 'standard', 'ai'],
        'ai': ['quick', 'preview', 'export'],
        'preview': ['export', 'share', 'edit'],
        'export': ['share', 'preview'],
        'projects': ['capture', 'preview', 'export'],
      };

      final related = relatedMap[currentAction] ?? ['capture', 'standard', 'quick'];
      final recommendations = <Map<String, dynamic>>[];

      for (final action in related.take(limit)) {
        final actionInfo = _getActionInfo(action);
        if (actionInfo != null) {
          recommendations.add({
            ...actionInfo,
            'reason': '与「${_getActionDisplayName(currentAction)}」相关的功能',
          });
        }
      }

      return recommendations;
    } catch (e) {
      debugPrint('[Recommendation] 相关推荐失败: $e');
      return [];
    }
  }

  /// 个性化推荐：基于用户偏好和项目状态推荐
  List<Map<String, dynamic>> getPersonalizedRecommendations({
    required int skillLevel,
    required String preferredCategory,
    int limit = 3,
  }) {
    try {
      final recommendations = <Map<String, dynamic>>[];

      // 基于技能等级
      if (skillLevel == 1) {
        recommendations.add(_buildRecommendation('quick', '快速体验模式', '无需完整拍摄，快速生成体验版', Icons.bolt, '适合新手入门'));
        recommendations.add(_buildRecommendation('capture', '一键生成', '拍照即可自动生成手写字体', Icons.auto_awesome, '最简单的创建方式'));
      } else if (skillLevel == 2) {
        recommendations.add(_buildRecommendation('standard', '标准字表模式', '使用标准字表逐字拍摄', Icons.grid_on, '生成完整字体的最佳方式'));
        recommendations.add(_buildRecommendation('free', '自由拍摄', '灵活拍摄任意字符', Icons.camera_alt, '自由创作'));
      } else {
        recommendations.add(_buildRecommendation('ai', 'AI 智能生成', '通过文字描述生成字体', Icons.auto_awesome_outlined, '高级创作方式'));
        recommendations.add(_buildRecommendation('preview', '增强预览', '高级预览和调整功能', Icons.preview, '精细化调整'));
      }

      // 基于偏好类别
      if (preferredCategory == 'standard') {
        recommendations.add(_buildRecommendation('standard', '继续字表创作', '使用标准字表继续创作', Icons.play_circle_outline, '基于您的偏好'));
      } else if (preferredCategory == 'ai') {
        recommendations.add(_buildRecommendation('ai', 'AI 风格探索', '探索更多 AI 字体风格', Icons.explore, '基于您的偏好'));
      }

      return recommendations.take(limit).toList();
    } catch (e) {
      debugPrint('[Recommendation] 个性化推荐失败: $e');
      return [];
    }
  }

  /// 获取使用统计（供推荐引擎参考）
  Map<String, dynamic> getUsageStats() {
    final actionCounts = <String, int>{};
    for (final action in _usageHistory) {
      final key = action['action'] as String? ?? 'unknown';
      actionCounts[key] = (actionCounts[key] ?? 0) + 1;
    }

    final now = DateTime.now();
    final todayCount = _usageHistory.where((a) {
      final ts = DateTime.tryParse(a['timestamp'] as String? ?? '');
      return ts != null && now.difference(ts).inDays == 0;
    }).length;

    return {
      'totalActions': _usageHistory.length,
      'todayActions': todayCount,
      'actionCounts': actionCounts,
      'mostUsedAction': actionCounts.isNotEmpty
          ? actionCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key
          : null,
    };
  }

  // ── 辅助方法 ──

  Map<String, dynamic>? _getActionInfo(String action) {
    final infoMap = <String, Map<String, dynamic>>{
      'capture': {'title': '一键生成', 'desc': '拍照自动生成手写字体', 'icon': Icons.auto_awesome, 'action': 'capture'},
      'standard': {'title': '标准字表', 'desc': '使用标准字表逐字拍摄', 'icon': Icons.grid_on, 'action': 'standard'},
      'quick': {'title': '快速体验', 'desc': '快速生成体验版字体', 'icon': Icons.bolt, 'action': 'quick'},
      'free': {'title': '自由拍摄', 'desc': '灵活拍摄任意字符', 'icon': Icons.camera_alt, 'action': 'free'},
      'ai': {'title': 'AI 生成', 'desc': 'AI 自动生成独特字体', 'icon': Icons.auto_awesome_outlined, 'action': 'ai'},
      'preview': {'title': '字体预览', 'desc': '预览和调整字体效果', 'icon': Icons.preview, 'action': 'preview'},
      'export': {'title': '导出字体', 'desc': '导出为 TTF/OTF 文件', 'icon': Icons.file_download, 'action': 'export'},
      'projects': {'title': '我的字体', 'desc': '管理所有字体项目', 'icon': Icons.folder, 'action': 'projects'},
    };
    return infoMap[action];
  }

  String _getActionDisplayName(String action) {
    final names = {
      'capture': '一键生成',
      'standard': '标准字表',
      'quick': '快速体验',
      'free': '自由拍摄',
      'ai': 'AI 生成',
      'preview': '字体预览',
      'export': '导出字体',
      'projects': '我的字体',
    };
    return names[action] ?? action;
  }

  Map<String, dynamic> _buildRecommendation(
    String action, String title, String desc, IconData icon, String reason,
  ) {
    return {
      'title': title,
      'desc': desc,
      'icon': icon,
      'action': action,
      'reason': reason,
    };
  }

  List<Map<String, dynamic>> _getDefaultRecommendations(int count) {
    return [
      _buildRecommendation('capture', '一键生成字体', '拍照自动生成手写字体', Icons.auto_awesome, '推荐的入门方式'),
      _buildRecommendation('standard', '标准字表模式', '使用标准字表逐字拍摄', Icons.grid_on, '生成完整字体'),
      _buildRecommendation('ai', 'AI 智能生成', '通过文字描述生成字体', Icons.auto_awesome_outlined, '创新创作方式'),
    ].take(count).toList();
  }

  /// 清除使用历史
  Future<void> clearHistory() async {
    _usageHistory.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_usageHistoryKey);
    } catch (_) {}
  }
}

// ═══════════════════════════════════════════════════════════
// 社区服务：社区帖子、话题、排行榜、活动
// ═══════════════════════════════════════════════════════════

/// 社区帖子数据模型
class CommunityPost {
  final String id;
  final String authorId;
  final String authorName;
  final String title;
  final String content;
  final String category; // showcase, tutorial, question, discussion
  final List<String> tags;
  final int likeCount;
  final int commentCount;
  final int viewCount;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isPinned;

  CommunityPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.title,
    required this.content,
    this.category = 'discussion',
    this.tags = const [],
    this.likeCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    DateTime? createdAt,
    this.updatedAt,
    this.isPinned = false,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'authorId': authorId,
        'authorName': authorName,
        'title': title,
        'content': content,
        'category': category,
        'tags': tags,
        'likeCount': likeCount,
        'commentCount': commentCount,
        'viewCount': viewCount,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'isPinned': isPinned,
      };

  factory CommunityPost.fromJson(Map<String, dynamic> json) => CommunityPost(
        id: json['id'] as String,
        authorId: json['authorId'] as String? ?? '',
        authorName: json['authorName'] as String? ?? '',
        title: json['title'] as String,
        content: json['content'] as String,
        category: json['category'] as String? ?? 'discussion',
        tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
        likeCount: json['likeCount'] as int? ?? 0,
        commentCount: json['commentCount'] as int? ?? 0,
        viewCount: json['viewCount'] as int? ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : null,
        isPinned: json['isPinned'] as bool? ?? false,
      );
}

/// 社区话题数据模型
class CommunityTopic {
  final String id;
  final String name;
  final String description;
  final String icon;
  final int postCount;
  final int participantCount;
  final DateTime createdAt;
  final bool isHot;

  CommunityTopic({
    required this.id,
    required this.name,
    required this.description,
    this.icon = '💬',
    this.postCount = 0,
    this.participantCount = 0,
    DateTime? createdAt,
    this.isHot = false,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'icon': icon,
        'postCount': postCount,
        'participantCount': participantCount,
        'createdAt': createdAt.toIso8601String(),
        'isHot': isHot,
      };

  factory CommunityTopic.fromJson(Map<String, dynamic> json) => CommunityTopic(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        icon: json['icon'] as String? ?? '💬',
        postCount: json['postCount'] as int? ?? 0,
        participantCount: json['participantCount'] as int? ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
        isHot: json['isHot'] as bool? ?? false,
      );
}

/// 社区排行榜条目
class LeaderboardEntry {
  final String userId;
  final String userName;
  final String avatar;
  final int score;
  final int rank;
  final Map<String, dynamic> stats; // {projects: n, likes: n, shares: n}

  LeaderboardEntry({
    required this.userId,
    required this.userName,
    this.avatar = '',
    this.score = 0,
    this.rank = 0,
    this.stats = const {},
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'userName': userName,
        'avatar': avatar,
        'score': score,
        'rank': rank,
        'stats': stats,
      };

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) => LeaderboardEntry(
        userId: json['userId'] as String,
        userName: json['userName'] as String? ?? '',
        avatar: json['avatar'] as String? ?? '',
        score: json['score'] as int? ?? 0,
        rank: json['rank'] as int? ?? 0,
        stats: json['stats'] as Map<String, dynamic>? ?? {},
      );
}

/// 社区活动数据模型
class CommunityActivity {
  final String id;
  final String title;
  final String description;
  final String type; // challenge, contest, workshop, meetup
  final DateTime startTime;
  final DateTime endTime;
  final int participantCount;
  final int maxParticipants;
  final String? rewardDescription;
  final bool isActive;

  CommunityActivity({
    required this.id,
    required this.title,
    required this.description,
    this.type = 'challenge',
    required this.startTime,
    required this.endTime,
    this.participantCount = 0,
    this.maxParticipants = 100,
    this.rewardDescription,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'type': type,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'participantCount': participantCount,
        'maxParticipants': maxParticipants,
        'rewardDescription': rewardDescription,
        'isActive': isActive,
      };

  factory CommunityActivity.fromJson(Map<String, dynamic> json) => CommunityActivity(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        type: json['type'] as String? ?? 'challenge',
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: DateTime.parse(json['endTime'] as String),
        participantCount: json['participantCount'] as int? ?? 0,
        maxParticipants: json['maxParticipants'] as int? ?? 100,
        rewardDescription: json['rewardDescription'] as String?,
        isActive: json['isActive'] as bool? ?? true,
      );
}

/// 社区服务
///
/// 功能：
/// - 社区帖子管理（发布、浏览、搜索）
/// - 社区话题管理（创建、浏览热门话题）
/// - 社区排行榜（贡献排名、活跃排名）
/// - 社区活动管理（创建、参与活动）
class CommunityService {
  static final CommunityService _instance = CommunityService._();
  static CommunityService get instance => _instance;
  CommunityService._();

  static const String _postsKey = 'community_posts';
  static const String _topicsKey = 'community_topics';
  static const String _activitiesKey = 'community_activities';
  static const String _leaderboardKey = 'community_leaderboard';
  static const int _maxPosts = 500;

  final List<CommunityPost> _posts = [];
  final List<CommunityTopic> _topics = [];
  final List<CommunityActivity> _activities = [];
  final List<LeaderboardEntry> _leaderboard = [];

  /// 获取帖子列表
  List<CommunityPost> get posts => List.unmodifiable(_posts);

  /// 获取话题列表
  List<CommunityTopic> get topics => List.unmodifiable(_topics);

  /// 获取活动列表
  List<CommunityActivity> get activities => List.unmodifiable(_activities);

  /// 获取排行榜
  List<LeaderboardEntry> get leaderboard => List.unmodifiable(_leaderboard);

  /// 初始化社区服务
  Future<void> init() async {
    try {
      await _loadPosts();
      await _loadTopics();
      await _loadActivities();
      await _loadLeaderboard();

      // 如果没有默认话题，创建默认话题
      if (_topics.isEmpty) {
        _createDefaultTopics();
      }

      debugPrint('[Community] 初始化完成: ${_posts.length} 帖子, ${_topics.length} 话题');
    } catch (e) {
      debugPrint('[Community] 初始化失败: $e');
    }
  }

  /// 创建默认话题
  void _createDefaultTopics() {
    _topics.addAll([
      CommunityTopic(id: 'showcase', name: '作品展示', description: '展示你的手写字体作品', icon: '🎨', isHot: true),
      CommunityTopic(id: 'tutorial', name: '教程分享', description: '分享字体创作技巧和教程', icon: '📚'),
      CommunityTopic(id: 'question', name: '问答求助', description: '遇到问题？寻求社区帮助', icon: '❓'),
      CommunityTopic(id: 'discussion', name: '交流讨论', description: '关于字体设计的交流讨论', icon: '💬', isHot: true),
      CommunityTopic(id: 'feedback', name: '反馈建议', description: '对应用的反馈和建议', icon: '💡'),
    ]);
    _saveTopics();
  }

  /// 发布帖子
  Future<CommunityPost?> createPost({
    required String title,
    required String content,
    required String authorName,
    String category = 'discussion',
    List<String> tags = const [],
  }) async {
    try {
      final post = CommunityPost(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        authorId: 'local_user',
        authorName: authorName,
        title: title,
        content: content,
        category: category,
        tags: tags,
      );

      _posts.insert(0, post);
      // 限制帖子数量
      while (_posts.length > _maxPosts) {
        _posts.removeLast();
      }
      await _savePosts();

      debugPrint('[Community] 帖子已发布: $title');
      return post;
    } catch (e) {
      debugPrint('[Community] 发布帖子失败: $e');
      return null;
    }
  }

  /// 搜索帖子
  List<CommunityPost> searchPosts(String query, {String? category}) {
    final lowerQuery = query.toLowerCase();
    return _posts.where((post) {
      if (category != null && post.category != category) return false;
      return post.title.toLowerCase().contains(lowerQuery) ||
          post.content.toLowerCase().contains(lowerQuery) ||
          post.tags.any((tag) => tag.toLowerCase().contains(lowerQuery));
    }).toList();
  }

  /// 按话题获取帖子
  List<CommunityPost> getPostsByTopic(String topicId) {
    return _posts.where((post) => post.category == topicId).toList();
  }

  /// 获取热门帖子（按点赞数排序）
  List<CommunityPost> getHotPosts({int limit = 10}) {
    final sorted = List<CommunityPost>.from(_posts)
      ..sort((a, b) => b.likeCount.compareTo(a.likeCount));
    return sorted.take(limit).toList();
  }

  /// 获取最新帖子
  List<CommunityPost> getRecentPosts({int limit = 20}) {
    return _posts.take(limit).toList();
  }

  /// 获取热门话题
  List<CommunityTopic> getHotTopics() {
    return _topics.where((t) => t.isHot).toList();
  }

  /// 创建社区活动
  Future<CommunityActivity?> createActivity({
    required String title,
    required String description,
    required DateTime startTime,
    required DateTime endTime,
    String type = 'challenge',
    int maxParticipants = 100,
    String? rewardDescription,
  }) async {
    try {
      final activity = CommunityActivity(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        description: description,
        type: type,
        startTime: startTime,
        endTime: endTime,
        maxParticipants: maxParticipants,
        rewardDescription: rewardDescription,
      );

      _activities.insert(0, activity);
      await _saveActivities();

      debugPrint('[Community] 活动已创建: $title');
      return activity;
    } catch (e) {
      debugPrint('[Community] 创建活动失败: $e');
      return null;
    }
  }

  /// 获取进行中的活动
  List<CommunityActivity> getActiveActivities() {
    final now = DateTime.now();
    return _activities.where((a) => a.isActive && a.startTime.isBefore(now) && a.endTime.isAfter(now)).toList();
  }

  /// 获取即将开始的活动
  List<CommunityActivity> getUpcomingActivities() {
    final now = DateTime.now();
    return _activities.where((a) => a.isActive && a.startTime.isAfter(now)).toList();
  }

  /// 更新排行榜
  Future<void> updateLeaderboard({
    required String userId,
    required String userName,
    required int score,
    Map<String, dynamic>? stats,
  }) async {
    try {
      final index = _leaderboard.indexWhere((e) => e.userId == userId);
      if (index >= 0) {
        _leaderboard[index] = LeaderboardEntry(
          userId: userId,
          userName: userName,
          score: score,
          stats: stats ?? _leaderboard[index].stats,
        );
      } else {
        _leaderboard.add(LeaderboardEntry(
          userId: userId,
          userName: userName,
          score: score,
          stats: stats ?? {},
        ));
      }

      // 按分数排序并更新排名
      _leaderboard.sort((a, b) => b.score.compareTo(a.score));
      for (int i = 0; i < _leaderboard.length; i++) {
        _leaderboard[i] = LeaderboardEntry(
          userId: _leaderboard[i].userId,
          userName: _leaderboard[i].userName,
          avatar: _leaderboard[i].avatar,
          score: _leaderboard[i].score,
          rank: i + 1,
          stats: _leaderboard[i].stats,
        );
      }

      await _saveLeaderboard();
      debugPrint('[Community] 排行榜已更新');
    } catch (e) {
      debugPrint('[Community] 更新排行榜失败: $e');
    }
  }

  /// 获取排行榜前N名
  List<LeaderboardEntry> getTopRankings({int limit = 10}) {
    return _leaderboard.take(limit).toList();
  }

  /// 获取社区统计摘要
  Map<String, dynamic> getCommunityStats() {
    final now = DateTime.now();
    return {
      'totalPosts': _posts.length,
      'totalTopics': _topics.length,
      'activeActivities': _activities.where((a) => a.isActive && a.startTime.isBefore(now) && a.endTime.isAfter(now)).length,
      'totalParticipants': _leaderboard.length,
      'hotTopics': _topics.where((t) => t.isHot).length,
    };
  }

  // ── 持久化方法 ──

  Future<void> _savePosts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_posts.map((e) => e.toJson()).toList());
      await prefs.setString(_postsKey, json);
    } catch (e) {
      debugPrint('[Community] 保存帖子失败: $e');
    }
  }

  Future<void> _loadPosts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_postsKey);
      if (json != null) {
        final list = jsonDecode(json) as List;
        _posts.clear();
        _posts.addAll(list.map((e) => CommunityPost.fromJson(e as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('[Community] 加载帖子失败: $e');
    }
  }

  Future<void> _saveTopics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_topics.map((e) => e.toJson()).toList());
      await prefs.setString(_topicsKey, json);
    } catch (e) {
      debugPrint('[Community] 保存话题失败: $e');
    }
  }

  Future<void> _loadTopics() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_topicsKey);
      if (json != null) {
        final list = jsonDecode(json) as List;
        _topics.clear();
        _topics.addAll(list.map((e) => CommunityTopic.fromJson(e as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('[Community] 加载话题失败: $e');
    }
  }

  Future<void> _saveActivities() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_activities.map((e) => e.toJson()).toList());
      await prefs.setString(_activitiesKey, json);
    } catch (e) {
      debugPrint('[Community] 保存活动失败: $e');
    }
  }

  Future<void> _loadActivities() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_activitiesKey);
      if (json != null) {
        final list = jsonDecode(json) as List;
        _activities.clear();
        _activities.addAll(list.map((e) => CommunityActivity.fromJson(e as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('[Community] 加载活动失败: $e');
    }
  }

  Future<void> _saveLeaderboard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_leaderboard.map((e) => e.toJson()).toList());
      await prefs.setString(_leaderboardKey, json);
    } catch (e) {
      debugPrint('[Community] 保存排行榜失败: $e');
    }
  }

  Future<void> _loadLeaderboard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_leaderboardKey);
      if (json != null) {
        final list = jsonDecode(json) as List;
        _leaderboard.clear();
        _leaderboard.addAll(list.map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('[Community] 加载排行榜失败: $e');
    }
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
  await CompatibilityService.instance.init(); // 初始化兼容性服务
  await CommunityService.instance.init(); // 初始化社区服务
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

  // ── 同步状态显示 ──
  String _syncStatusText = '未同步';
  bool _isSyncing = false;
  int _conflictCount = 0;
  int _pendingSyncCount = 0;
  Timer? _syncStatusTimer;
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
    _initSyncStatusMonitor();
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
    _syncStatusTimer?.cancel();
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

  // ═══════════════════════════════════════════════════════════
  // 同步状态监控
  // ═══════════════════════════════════════════════════════════

  /// 初始化同步状态监控
  ///
  /// 定期检查同步状态，更新 UI 显示
  void _initSyncStatusMonitor() {
    // 每 30 秒检查一次同步状态
    _syncStatusTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        _updateSyncStatus();
      }
    });

    // 立即检查一次
    _updateSyncStatus();
  }

  /// 更新同步状态
  Future<void> _updateSyncStatus() async {
    try {
      final cloudSync = CloudSyncService.instance;
      final summary = cloudSync.getSyncSummary();

      if (mounted) {
        setState(() {
          _isSyncing = summary['syncState'] == 'syncing';
          _conflictCount = (summary['conflictCount'] as int?) ?? 0;
          _pendingSyncCount = (summary['pendingCount'] as int?) ?? 0;

          if (_isSyncing) {
            _syncStatusText = '同步中...';
          } else if (_conflictCount > 0) {
            _syncStatusText = '$_conflictCount 个冲突待解决';
          } else if (_pendingSyncCount > 0) {
            _syncStatusText = '$_pendingSyncCount 个项目待同步';
          } else {
            final lastSync = summary['lastSyncTime'] as String?;
            if (lastSync != null) {
              final lastSyncTime = DateTime.tryParse(lastSync);
              if (lastSyncTime != null) {
                final diff = DateTime.now().difference(lastSyncTime);
                if (diff.inMinutes < 1) {
                  _syncStatusText = '刚刚同步';
                } else if (diff.inHours < 1) {
                  _syncStatusText = '${diff.inMinutes} 分钟前同步';
                } else if (diff.inDays < 1) {
                  _syncStatusText = '${diff.inHours} 小时前同步';
                } else {
                  _syncStatusText = '${diff.inDays} 天前同步';
                }
              } else {
                _syncStatusText = '已同步';
              }
            } else {
              _syncStatusText = '未同步';
            }
          }
        });
      }
    } catch (e) {
      debugPrint('[SyncStatus] 更新同步状态失败: $e');
    }
  }

  /// 执行智能同步
  Future<void> _performSmartSync() async {
    if (_isSyncing) return;

    setState(() {
      _isSyncing = true;
      _syncStatusText = '同步中...';
    });

    try {
      final cloudSync = CloudSyncService.instance;
      final error = await cloudSync.smartSync();

      if (mounted) {
        setState(() {
          _isSyncing = false;
          if (error != null) {
            _syncStatusText = '同步失败: $error';
          } else {
            _syncStatusText = '同步完成';
          }
        });

        // 2 秒后刷新状态
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _updateSyncStatus();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncStatusText = '同步异常';
        });
      }
    }
  }

  /// 检测并处理冲突
  Future<void> _checkConflicts() async {
    try {
      final cloudSync = CloudSyncService.instance;
      final conflicts = await cloudSync.detectConflicts();

      if (conflicts.isNotEmpty && mounted) {
        // 显示冲突通知
        NotificationService.instance.show(
 title: '检测到同步冲突',
 body: '${conflicts.length} 个项目存在同步冲突，请手动解决',
 category: NotificationCategory.sync,
 priority: NotificationPriority.high,
        );
      }
    } catch (e) {
      debugPrint('[SyncStatus] 冲突检测失败: $e');
    }
  }

  /// 获取同步状态文本
  String get syncStatusText => _syncStatusText;

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
