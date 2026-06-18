import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'models/project.dart';
import 'screens/home_screen.dart';
import 'screens/auto_generate_screen.dart';
import 'screens/capture_screen.dart';
import 'screens/processing_screen.dart';
import 'screens/preview_screen.dart';
import 'screens/writing_tips_screen.dart';
import 'screens/charset_guide_screen.dart';
import 'screens/ocr_settings_screen.dart';
import 'services/recognition_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WriteFontApp());
}

class WriteFontApp extends StatefulWidget {
  const WriteFontApp({super.key});

  @override
  State<WriteFontApp> createState() => _WriteFontAppState();
}

class _WriteFontAppState extends State<WriteFontApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      themeMode: ThemeMode.system,
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(
              builder: (_) => const HomeScreen(),
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
          case '/auto-generate':
            final imageBytes = (settings.arguments as Map<String, dynamic>?)?['imageBytes'] as Uint8List?;
            if (imageBytes != null) {
              return MaterialPageRoute(
                builder: (_) => AutoGenerateScreen(imageBytes: imageBytes),
              );
            }
            return MaterialPageRoute(builder: (_) => const HomeScreen());
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
              builder: (_) => const HomeScreen(),
            );
        }
      },
    );
  }
}
