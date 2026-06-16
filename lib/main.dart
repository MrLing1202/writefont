import 'package:flutter/cupertino.dart';

import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WriteFontApp());
}

/// 手迹造字 - WriteFont iOS 客户端
class WriteFontApp extends StatelessWidget {
  const WriteFontApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      title: '手迹造字',
      debugShowCheckedModeBanner: false,
      theme: const CupertinoThemeData(
        brightness: Brightness.light,
        primaryColor: CupertinoColors.activeBlue,
        scaffoldBackgroundColor: CupertinoColors.systemBackground,
        barBackgroundColor: Color(0xF0F9F9F9),
        textTheme: CupertinoTextThemeData(
          primaryColor: CupertinoColors.activeBlue,
          textStyle: TextStyle(
            fontFamily: '.SF Pro Text',
            fontSize: 16,
            color: CupertinoColors.label,
          ),
          navTitleTextStyle: TextStyle(
            fontFamily: '.SF Pro Display',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: CupertinoColors.label,
          ),
          navLargeTitleTextStyle: TextStyle(
            fontFamily: '.SF Pro Display',
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: CupertinoColors.label,
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
