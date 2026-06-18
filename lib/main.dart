import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/project.dart';
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
import 'dart:typed_data';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 预加载主题设置
  await AppConfigService.instance.getThemeMode();
  runApp(const WriteFontApp());
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadThemeMode();
    _checkOnboarding();
  }

  /// 检查是否已看过新手引导
  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('onboarding_seen') ?? false;
    if (mounted) {
      setState(() {
        _onboardingSeen = seen;
        _onboardingChecked = true;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RecognitionService.instance.dispose(); // 释放 ML Kit 资源
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      RecognitionService.instance.dispose();
    }
  }

  /// 加载主题模式设置
  Future<void> _loadThemeMode() async {
    final themeMode = await AppConfigService.instance.getThemeMode();
    if (mounted) {
      setState(() => _themeModeStr = themeMode);
    }
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '手迹造字 WriteFont',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4A6741),
        brightness: Brightness.light,
        fontFamily: null, // Use system font
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4A6741),
        brightness: Brightness.dark,
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      themeMode: _themeMode,
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            // 未检查完时显示加载占位，首次使用显示引导
            if (!_onboardingChecked) {
              return MaterialPageRoute(
                builder: (_) => const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            if (!_onboardingSeen) {
              return MaterialPageRoute(
                builder: (_) => const OnboardingScreen(),
              );
            }
            return MaterialPageRoute(
              builder: (_) => HomeScreen(
                onThemeChanged: () => _loadThemeMode(),
              ),
            );
          case '/writing-tips':
            return MaterialPageRoute(
              builder: (_) => const WritingTipsScreen(),
            );
          case '/charset-guide':
            return MaterialPageRoute(
              builder: (_) => const CharsetGuideScreen(),
            );
          case '/ocr-settings':
            return MaterialPageRoute(
              builder: (_) => const OcrSettingsScreen(),
            );
          case '/my-fonts':
            return MaterialPageRoute(
              builder: (_) => const ProjectListScreen(),
            );
          case '/settings':
            return MaterialPageRoute(
              builder: (_) => SettingsScreen(
                onThemeChanged: () => _loadThemeMode(),
              ),
            );
          case '/auto-generate':
            final imageBytes = (settings.arguments as Map<String, dynamic>?)?['imageBytes'] as Uint8List?;
            if (imageBytes != null) {
              return MaterialPageRoute(
                builder: (_) => AutoGenerateScreen(imageBytes: imageBytes),
              );
            }
            return MaterialPageRoute(builder: (_) => HomeScreen(
              onThemeChanged: () => _loadThemeMode(),
            ));
          case '/capture':
            final charset = (settings.arguments as Map<String, dynamic>?)?['charset'] as List<String>?;
            return MaterialPageRoute(
              builder: (_) => CaptureScreen(charset: charset),
            );
          case '/processing':
            final args = settings.arguments as Map<String, dynamic>;
            final images = args['images'] as List<Uint8List>;
            final charset = args['charset'] as List<String>?;
            return MaterialPageRoute(
              builder: (_) => ProcessingScreen(
                sourceImages: images,
                charset: charset,
              ),
            );
          case '/preview':
            final args = settings.arguments as Map<String, dynamic>;
            final project = args['project'] as FontProject;
            return MaterialPageRoute(
              builder: (_) => PreviewScreen(project: project),
            );
          default:
            return MaterialPageRoute(
              builder: (_) => HomeScreen(
                onThemeChanged: () => _loadThemeMode(),
              ),
            );
        }
      },
    );
  }
}
