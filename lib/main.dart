import 'dart:convert';
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
