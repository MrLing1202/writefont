import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'models/project.dart';
import 'screens/home_screen.dart';
import 'screens/capture_screen.dart';
import 'screens/processing_screen.dart';
import 'screens/preview_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WriteFontApp());
}

class WriteFontApp extends StatelessWidget {
  const WriteFontApp({super.key});

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
        cardTheme: CardTheme(
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
        cardTheme: CardTheme(
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
          case '/capture':
            return MaterialPageRoute(
              builder: (_) => const CaptureScreen(),
            );
          case '/processing':
            final args = settings.arguments as Map<String, dynamic>;
            final images = args['images'] as List<Uint8List>;
            return MaterialPageRoute(
              builder: (_) => ProcessingScreen(sourceImages: images),
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
