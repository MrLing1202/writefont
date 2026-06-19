/// 语言切换服务
/// 管理应用语言的持久化和切换
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class LocaleService extends ChangeNotifier {
  static const String _keyLocale = 'app_locale';
  static const String _keyDateFormat = 'date_format';
  static const String _keyNumberFormat = 'number_format';

  static LocaleService? _instance;
  static LocaleService get instance => _instance ??= LocaleService._();
  LocaleService._();

  Locale _locale = const Locale('zh');
  Locale get locale => _locale;

  /// 日期格式类型
  DateFormatType _dateFormatType = DateFormatType.standard;
  DateFormatType get dateFormatType => _dateFormatType;

  /// 数字格式类型
  NumberFormatType _numberFormatType = NumberFormatType.standard;
  NumberFormatType get numberFormatType => _numberFormatType;

  /// 支持的语言列表
  static const List<Locale> supportedLocales = [
    Locale('zh'),
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
    Locale('fr'),
    Locale('de'),
    Locale('es'),
  ];

  /// 语言代码到显示名称的映射
  static const Map<String, String> localeNames = {
    'zh': '中文',
    'en': 'English',
    'ja': '日本語',
    'ko': '한국어',
    'fr': 'Français',
    'de': 'Deutsch',
    'es': 'Español',
  };

  /// 初始化，从持久化存储加载语言设置
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_keyLocale) ?? 'zh';
      _locale = Locale(code);
      final dateFormatIndex = prefs.getInt(_keyDateFormat) ?? 0;
      _dateFormatType = DateFormatType.values[dateFormatIndex];
      final numberFormatIndex = prefs.getInt(_keyNumberFormat) ?? 0;
      _numberFormatType = NumberFormatType.values[numberFormatIndex];
      notifyListeners();
    } catch (e) {
      debugPrint('加载语言设置失败: $e');
    }
  }

  /// 设置日期格式类型
  Future<void> setDateFormatType(DateFormatType type) async {
    if (_dateFormatType == type) return;
    _dateFormatType = type;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyDateFormat, type.index);
    } catch (e) {
      debugPrint('保存日期格式设置失败: $e');
    }
  }

  /// 设置数字格式类型
  Future<void> setNumberFormatType(NumberFormatType type) async {
    if (_numberFormatType == type) return;
    _numberFormatType = type;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyNumberFormat, type.index);
    } catch (e) {
      debugPrint('保存数字格式设置失败: $e');
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

  /// 格式化日期
  String formatDate(DateTime date) {
    try {
      final localeCode = _locale.languageCode;
      switch (_dateFormatType) {
        case DateFormatType.standard:
          return DateFormat.yMMMd(localeCode).format(date);
        case DateFormatType.short:
          return DateFormat.yMd(localeCode).format(date);
        case DateFormatType.long:
          return DateFormat.yMMMMd(localeCode).format(date);
        case DateFormatType.relative:
          return _formatRelativeDate(date);
      }
    } catch (e) {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }

  /// 格式化相对时间
  String _formatRelativeDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inMinutes < 1) {
      return _getLocalizedString('just_now');
    } else if (diff.inHours < 1) {
      return _getLocalizedString('minutes_ago', [diff.inMinutes]);
    } else if (diff.inDays < 1) {
      return _getLocalizedString('hours_ago', [diff.inHours]);
    } else if (diff.inDays < 7) {
      return _getLocalizedString('days_ago', [diff.inDays]);
    } else {
      return formatDate(date);
    }
  }

  /// 获取本地化字符串
  String _getLocalizedString(String key, [List<dynamic>? args]) {
    final strings = _localizedStrings[_locale.languageCode] ?? _localizedStrings['zh']!;
    String? template = strings[key];
    if (template == null) return key;
    
    if (args != null) {
      for (int i = 0; i < args.length; i++) {
        template = template!.replaceAll('{$i}', args[i].toString());
      }
    }
    return template!;
  }

  /// 本地化字符串映射
  static const Map<String, Map<String, String>> _localizedStrings = {
    'zh': {
      'just_now': '刚刚',
      'minutes_ago': '{0}分钟前',
      'hours_ago': '{0}小时前',
      'days_ago': '{0}天前',
      'error_network': '网络连接失败，请检查网络设置',
      'error_timeout': '请求超时，请稍后重试',
      'error_unknown': '发生未知错误',
      'error_permission': '权限不足，请在设置中开启相关权限',
      'error_storage': '存储空间不足',
      'error_format': '数据格式错误',
      'success_save': '保存成功',
      'success_delete': '删除成功',
      'success_export': '导出成功',
      'confirm_delete': '确定要删除吗？',
      'confirm_cancel': '确定要取消当前操作吗？',
      'loading': '加载中...',
      'retry': '重试',
      'cancel': '取消',
      'confirm': '确认',
    },
    'en': {
      'just_now': 'Just now',
      'minutes_ago': '{0} minutes ago',
      'hours_ago': '{0} hours ago',
      'days_ago': '{0} days ago',
      'error_network': 'Network connection failed, please check your network settings',
      'error_timeout': 'Request timed out, please try again later',
      'error_unknown': 'An unknown error occurred',
      'error_permission': 'Insufficient permissions, please enable in settings',
      'error_storage': 'Insufficient storage space',
      'error_format': 'Data format error',
      'success_save': 'Saved successfully',
      'success_delete': 'Deleted successfully',
      'success_export': 'Exported successfully',
      'confirm_delete': 'Are you sure you want to delete?',
      'confirm_cancel': 'Are you sure you want to cancel?',
      'loading': 'Loading...',
      'retry': 'Retry',
      'cancel': 'Cancel',
      'confirm': 'Confirm',
    },
    'ja': {
      'just_now': 'たった今',
      'minutes_ago': '{0}分前',
      'hours_ago': '{0}時間前',
      'days_ago': '{0}日前',
      'error_network': 'ネットワーク接続に失敗しました。ネットワーク設定を確認してください',
      'error_timeout': 'リクエストがタイムアウトしました。後でもう一度お試しください',
      'error_unknown': '不明なエラーが発生しました',
      'error_permission': '権限が不足しています。設定で権限を有効にしてください',
      'error_storage': 'ストレージスペースが不足しています',
      'error_format': 'データ形式エラー',
      'success_save': '保存しました',
      'success_delete': '削除しました',
      'success_export': 'エクスポートしました',
      'confirm_delete': '削除してもよろしいですか？',
      'confirm_cancel': '現在の操作をキャンセルしてもよろしいですか？',
      'loading': '読み込み中...',
      'retry': '再試行',
      'cancel': 'キャンセル',
      'confirm': '確認',
    },
    'ko': {
      'just_now': '방금',
      'minutes_ago': '{0}분 전',
      'hours_ago': '{0}시간 전',
      'days_ago': '{0}일 전',
      'error_network': '네트워크 연결에 실패했습니다. 네트워크 설정을 확인하세요',
      'error_timeout': '요청 시간이 초과되었습니다. 나중에 다시 시도하세요',
      'error_unknown': '알 수 없는 오류가 발생했습니다',
      'error_permission': '권한이 부족합니다. 설정에서 권한을 활성화하세요',
      'error_storage': '저장 공간이 부족합니다',
      'error_format': '데이터 형식 오류',
      'success_save': '저장 완료',
      'success_delete': '삭제 완료',
      'success_export': '내보내기 완료',
      'confirm_delete': '삭제하시겠습니까?',
      'confirm_cancel': '현재 작업을 취소하시겠습니까?',
      'loading': '로딩 중...',
      'retry': '재시도',
      'cancel': '취소',
      'confirm': '확인',
    },
    'fr': {
      'just_now': 'À l\'instant',
      'minutes_ago': 'Il y a {0} minutes',
      'hours_ago': 'Il y a {0} heures',
      'days_ago': 'Il y a {0} jours',
      'error_network': 'Échec de la connexion réseau, veuillez vérifier vos paramètres réseau',
      'error_timeout': 'La requête a expiré, veuillez réessayer plus tard',
      'error_unknown': 'Une erreur inconnue s\'est produite',
      'error_permission': 'Permissions insuffisantes, veuillez les activer dans les paramètres',
      'error_storage': 'Espace de stockage insuffisant',
      'error_format': 'Erreur de format de données',
      'success_save': 'Enregistré avec succès',
      'success_delete': 'Supprimé avec succès',
      'success_export': 'Exporté avec succès',
      'confirm_delete': 'Êtes-vous sûr de vouloir supprimer ?',
      'confirm_cancel': 'Êtes-vous sûr de vouloir annuler ?',
      'loading': 'Chargement...',
      'retry': 'Réessayer',
      'cancel': 'Annuler',
      'confirm': 'Confirmer',
    },
    'de': {
      'just_now': 'Gerade eben',
      'minutes_ago': 'Vor {0} Minuten',
      'hours_ago': 'Vor {0} Stunden',
      'days_ago': 'Vor {0} Tagen',
      'error_network': 'Netzwerkverbindung fehlgeschlagen, bitte überprüfen Sie Ihre Netzwerkeinstellungen',
      'error_timeout': 'Anfrage abgelaufen, bitte versuchen Sie es später erneut',
      'error_unknown': 'Ein unbekannter Fehler ist aufgetreten',
      'error_permission': 'Unzureichende Berechtigungen, bitte in den Einstellungen aktivieren',
      'error_storage': 'Nicht genügend Speicherplatz',
      'error_format': 'Datenformatfehler',
      'success_save': 'Erfolgreich gespeichert',
      'success_delete': 'Erfolgreich gelöscht',
      'success_export': 'Erfolgreich exportiert',
      'confirm_delete': 'Sind Sie sicher, dass Sie löschen möchten?',
      'confirm_cancel': 'Sind Sie sicher, dass Sie abbrechen möchten?',
      'loading': 'Laden...',
      'retry': 'Erneut versuchen',
      'cancel': 'Abbrechen',
      'confirm': 'Bestätigen',
    },
    'es': {
      'just_now': 'Ahora mismo',
      'minutes_ago': 'Hace {0} minutos',
      'hours_ago': 'Hace {0} horas',
      'days_ago': 'Hace {0} días',
      'error_network': 'Error de conexión de red, verifique su configuración de red',
      'error_timeout': 'La solicitud ha expirado, inténtelo de nuevo más tarde',
      'error_unknown': 'Se produjo un error desconocido',
      'error_permission': 'Permisos insuficientes, actívelos en la configuración',
      'error_storage': 'Espacio de almacenamiento insuficiente',
      'error_format': 'Error de formato de datos',
      'success_save': 'Guardado exitosamente',
      'success_delete': 'Eliminado exitosamente',
      'success_export': 'Exportado exitosamente',
      'confirm_delete': '¿Está seguro de que desea eliminar?',
      'confirm_cancel': '¿Está seguro de que desea cancelar?',
      'loading': 'Cargando...',
      'retry': 'Reintentar',
      'cancel': 'Cancelar',
      'confirm': 'Confirmar',
    },
  };

  /// 格式化数字
  String formatNumber(num number, {int decimalDigits = 0}) {
    try {
      final localeCode = _locale.languageCode;
      switch (_numberFormatType) {
        case NumberFormatType.standard:
          return NumberFormat('#,##0.${'0' * decimalDigits}', localeCode).format(number);
        case NumberFormatType.compact:
          return NumberFormat.compact(locale: localeCode).format(number);
        case NumberFormatType.percent:
          return NumberFormat.percentPattern(localeCode).format(number);
        case NumberFormatType.scientific:
          return NumberFormat.scientificPattern(localeCode).format(number);
      }
    } catch (e) {
      return number.toString();
    }
  }

  /// 格式化货币
  String formatCurrency(num amount, {String? currencyCode}) {
    try {
      final localeCode = _locale.languageCode;
      final code = currencyCode ?? _getDefaultCurrencyCode(localeCode);
      return NumberFormat.currency(locale: localeCode, symbol: code).format(amount);
    } catch (e) {
      return amount.toString();
    }
  }

  /// 获取默认货币代码（含新增语言支持）
  String _getDefaultCurrencyCode(String localeCode) {
    switch (localeCode) {
      case 'zh': return '¥';    // 人民币
      case 'en': return '\$';   // 美元
      case 'ja': return '¥';    // 日元
      case 'ko': return '₩';    // 韩元
      case 'fr': return '€';    // 欧元
      case 'de': return '€';    // 欧元
      case 'es': return '€';    // 欧元
      default: return '\$';
    }
  }

  /// 获取错误提示
  String getErrorMessage(String errorKey, [List<dynamic>? args]) {
    return _getLocalizedString('error_$errorKey', args);
  }

  /// 获取成功提示
  String getSuccessMessage(String successKey, [List<dynamic>? args]) {
    return _getLocalizedString('success_$successKey', args);
  }

  /// 获取确认提示
  String getConfirmMessage(String confirmKey, [List<dynamic>? args]) {
    return _getLocalizedString('confirm_$confirmKey', args);
  }

  /// 获取通用提示
  String getMessage(String key, [List<dynamic>? args]) {
    return _getLocalizedString(key, args);
  }
}

/// 日期格式类型
enum DateFormatType {
  standard,  // 标准格式：Sep 12, 2023
  short,     // 短格式：9/12/2023
  long,      // 长格式：September 12, 2023
  relative,  // 相对时间：3小时前
}

/// 数字格式类型
enum NumberFormatType {
  standard,   // 标准格式：1,234
  compact,    // 紧凑格式：1.2K
  percent,    // 百分比：12%
  scientific, // 科学计数法：1.23E3
}
