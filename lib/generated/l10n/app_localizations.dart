import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationsDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen_l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure the following entry exists in your pubspec.yaml file:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata in an Info.plist file
/// that is located inside the Runner.xcworkspace bundle. To configure the
/// locales supported by your app, you'll need to edit this file.
///
/// First, open your project's ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// directory. You should see a standard Info.plist file. You'll need to
/// update the CFBundleLocalizations key to include the locales supported by
/// your app.
///
/// To add a new locale, you'll need to add a new entry to the
/// CFBundleLocalizations array. For example, to add support for French,
/// you would add the following entry:
///
/// ```xml
///   <key>CFBundleLocalizations</key>
///   <array>
///     <string>en</string>
///     <string>fr</string>
///   </array>
/// ```
///
/// ## iOS App Transport Security
///
/// To use the Flutter localization system on iOS, you'll need to make sure
/// your app has access to the internet. This is because the localization
/// files are downloaded from the internet. To do this, add the following
/// entry to your app's Info.plist file:
///
/// ```xml
///   <key>NSAppTransportSecurity</key>
///   <dict>
///     <key>NSAllowsArbitraryLoads</key>
///     <true/>
///   </dict>
/// ```

abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// List<LocalizationsDelegate<dynamic>> get localizationsDelegates => const [
  ///   AppLocalizations.delegate,
  ///   GlobalMaterialLocalizations.delegate,
  ///   GlobalWidgetsLocalizations.delegate,
  ///   GlobalCupertinoLocalizations.delegate,
  /// ];
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh'),
    Locale('en'),
    Locale('ja'),
  ];

  String get appName;
  String get appTitle;
  String get settings;
  String get cancel;
  String get confirm;
  String get close;
  String get save;
  String get delete;
  String get retry;
  String get back;
  String get start;
  String get done;
  String get skip;
  String get nextStep;
  String get prevStep;
  String get resetToDefault;
  String get welcomeToApp;
  String get welcomeSubtitle;
  String get createdProjects;
  String get recognizedChars;
  String get recentActivity;
  String get oneClickGenerate;
  String get oneClickGenerateDesc;
  String get standardCharset;
  String get standardCharsetDesc;
  String get quickExperience;
  String get quickExperienceDesc;
  String get freeCapture;
  String get freeCaptureDesc;
  String get myFonts;
  String myFontsSaved(int count);
  String get myFontsDesc;
  String get charOverview;
  String get charOverviewDesc;
  String get fontPreview;
  String get fontPreviewDesc;
  String get enhancedPreview;
  String get enhancedPreviewDesc;
  String get styleTransfer;
  String get styleTransferDesc;
  String get recommendStandard;
  String get justNow;
  String minutesAgo(int count);
  String hoursAgo(int count);
  String daysAgo(int count);
  String get onboardingWelcome;
  String get onboardingWelcomeDesc;
  String get onboardingStep1;
  String get onboardingStep1Title;
  String get onboardingStep1Desc;
  String get onboardingStep2;
  String get onboardingStep2Title;
  String get onboardingStep2Desc;
  String get onboardingStep3;
  String get onboardingStep3Title;
  String get onboardingStep3Desc;
  String get onboardingStartBtn;
  String get aiRecognizeAndFix;
  String get captureUpload;
  String get appearance;
  String get recognitionSettings;
  String get fontGeneration;
  String get storage;
  String get cloudSync;
  String get about;
  String get lightMode;
  String get darkMode;
  String get followSystem;
  String appearanceChanged(String mode);
  String get language;
  String get languageDesc;
  String get chinese;
  String get english;
  String get japanese;
  String languageChanged(String language);
  String get localRecognition;
  String get localRecognitionDesc;
  String get cloudRecognition;
  String get cloudRecognitionDesc;
  String get cloudConfig;
  String get cloudConfigDesc;
  String get switchedToLocal;
  String get switchedToCloud;
  String get threshold;
  String get thresholdDesc;
  String get contrast;
  String get contrastDesc;
  String get smoothness;
  String get smoothnessDesc;
  String get strokeWidth;
  String get strokeWidthDesc;
  String get paramsReset;
  String get exportSettings;
  String get exportSettingsDesc;
  String get importSettings;
  String get importSettingsDesc;
  String get clearTempFiles;
  String get clearTempFilesDesc;
  String get tempFilesCleared;
  String clearFailed(String error);
  String get settingsExported;
  String exportFailed(String error);
  String get settingsImported;
  String importFailed(String error);
  String get invalidSettingsFile;
  String get selectSettingsFile;
  String get settingsBackupSubject;
  String get settingsBackupText;
  String get cloudSyncDesc;
  String get version;
  String get openSourceLicense;
  String get viewSourceCode;
  String get cannotOpenLink;
  String get processing;
  String get generating;
  String get loading;
  String get networkError;
  String get unknownError;
  String get projectList;
  String get fontPreviewTitle;
  String get characterEdit;
  String get captureTitle;
  String get batchProcessing;
  String get ocrSettings;
  String get writingTips;
  String get charsetGuide;
  String get autoGenerate;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['zh', 'en', 'ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'zh': return AppLocalizationsZh();
    case 'en': return AppLocalizationsEn();
    case 'ja': return AppLocalizationsJa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
