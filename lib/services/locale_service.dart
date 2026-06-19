/// 语言切换服务
/// 管理应用语言的持久化和切换
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleService extends ChangeNotifier {
  static const String _keyLocale = 'app_locale';

  static LocaleService? _instance;
  static LocaleService get instance => _instance ??= LocaleService._();
  LocaleService._();

  Locale _locale = const Locale('zh');
  Locale get locale => _locale;

  /// 支持的语言列表
  static const List<Locale> supportedLocales = [
    Locale('zh'),
    Locale('en'),
    Locale('ja'),
  ];

  /// 语言代码到显示名称的映射
  static const Map<String, String> localeNames = {
    'zh': '中文',
    'en': 'English',
    'ja': '日本語',
  };

  /// 初始化，从持久化存储加载语言设置
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_keyLocale) ?? 'zh';
      _locale = Locale(code);
      notifyListeners();
    } catch (e) {
      debugPrint('加载语言设置失败: $e');
    }
  }

  /// 切换语言
  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLocale, locale.languageCode);
    } catch (e) {
      debugPrint('保存语言设置失败: $e');
    }
  }

  /// 获取当前语言的显示名称
  String get currentLocaleName => localeNames[_locale.languageCode] ?? '中文';
}
