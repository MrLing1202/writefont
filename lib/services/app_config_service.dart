/// 应用配置服务
/// 统一管理所有非 OCR 的应用配置，包括处理参数和外观设置
/// 所有配置通过 SharedPreferences 持久化，key 统一使用 'app_' 前缀
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfigService {
  // SharedPreferences keys（统一 'app_' 前缀）
  static const String _keyThreshold = 'app_threshold';
  static const String _keyContrast = 'app_contrast';
  static const String _keySmoothness = 'app_smoothness';
  static const String _keyStrokeWidth = 'app_stroke_width';
  static const String _keyThemeMode = 'app_theme_mode';

  // 默认值
  static const double defaultThreshold = 0.5;
  static const double defaultContrast = 1.0;
  static const double defaultSmoothness = 0.3;
  static const double defaultStrokeWidth = 1.0;
  static const String defaultThemeMode = 'system';

  static AppConfigService? _instance;
  static AppConfigService get instance => _instance ??= AppConfigService._();

  AppConfigService._();

  // ===== 处理参数 =====

  /// 获取阈值
  Future<double> getThreshold() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(_keyThreshold) ?? defaultThreshold;
    } catch (e) {
      debugPrint('读取阈值配置失败: $e');
      return defaultThreshold;
    }
  }

  /// 保存阈值
  Future<void> setThreshold(double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyThreshold, value);
    } catch (e) {
      debugPrint('保存阈值配置失败: $e');
    }
  }

  /// 获取对比度
  Future<double> getContrast() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(_keyContrast) ?? defaultContrast;
    } catch (e) {
      debugPrint('读取对比度配置失败: $e');
      return defaultContrast;
    }
  }

  /// 保存对比度
  Future<void> setContrast(double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyContrast, value);
    } catch (e) {
      debugPrint('保存对比度配置失败: $e');
    }
  }

  /// 获取平滑度
  Future<double> getSmoothness() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(_keySmoothness) ?? defaultSmoothness;
    } catch (e) {
      debugPrint('读取平滑度配置失败: $e');
      return defaultSmoothness;
    }
  }

  /// 保存平滑度
  Future<void> setSmoothness(double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keySmoothness, value);
    } catch (e) {
      debugPrint('保存平滑度配置失败: $e');
    }
  }

  /// 获取笔画宽度
  Future<double> getStrokeWidth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(_keyStrokeWidth) ?? defaultStrokeWidth;
    } catch (e) {
      debugPrint('读取笔画宽度配置失败: $e');
      return defaultStrokeWidth;
    }
  }

  /// 保存笔画宽度
  Future<void> setStrokeWidth(double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyStrokeWidth, value);
    } catch (e) {
      debugPrint('保存笔画宽度配置失败: $e');
    }
  }

  /// 重置所有处理参数为默认值
  Future<void> resetParams() async {
    await setThreshold(defaultThreshold);
    await setContrast(defaultContrast);
    await setSmoothness(defaultSmoothness);
    await setStrokeWidth(defaultStrokeWidth);
  }

  // ===== 外观设置 =====

  /// 获取主题模式（'light' / 'dark' / 'system'）
  Future<String> getThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyThemeMode) ?? defaultThemeMode;
    } catch (e) {
      debugPrint('读取主题模式配置失败: $e');
      return defaultThemeMode;
    }
  }

  /// 保存主题模式
  Future<void> setThemeMode(String mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyThemeMode, mode);
    } catch (e) {
      debugPrint('保存主题模式配置失败: $e');
    }
  }

  /// 获取深色模式状态（兼容旧接口）
  Future<bool> getDarkMode() async {
    final mode = await getThemeMode();
    return mode == 'dark';
  }

  /// 设置深色模式（兼容旧接口，切换 light/dark）
  Future<void> setDarkMode(bool value) async {
    await setThemeMode(value ? 'dark' : 'light');
  }
}
