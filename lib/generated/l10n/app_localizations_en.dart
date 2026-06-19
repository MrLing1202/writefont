import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'WriteFont';

  @override
  String get appTitle => 'WriteFont';

  @override
  String get settings => 'Settings';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get close => 'Close';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get retry => 'Retry';

  @override
  String get back => 'Back';

  @override
  String get start => 'Start';

  @override
  String get done => 'Done';

  @override
  String get skip => 'Skip';

  @override
  String get nextStep => 'Next';

  @override
  String get prevStep => 'Previous';

  @override
  String get resetToDefault => 'Reset to Default';

  @override
  String get welcomeToApp => 'Welcome to WriteFont';

  @override
  String get welcomeSubtitle => 'Turn your handwriting into a custom font';

  @override
  String get createdProjects => 'Projects';

  @override
  String get recognizedChars => 'Characters';

  @override
  String get recentActivity => 'Recent';

  @override
  String get oneClickGenerate => 'One-Click Generate';

  @override
  String get oneClickGenerateDesc => 'Take a photo and generate automatically';

  @override
  String get standardCharset => 'Standard Charset';

  @override
  String get standardCharsetDesc => 'Write 40 common characters, AI auto-recognition';

  @override
  String get quickExperience => 'Quick Try';

  @override
  String get quickExperienceDesc => 'Write just 10 characters to try';

  @override
  String get freeCapture => 'Free Capture';

  @override
  String get freeCaptureDesc => 'Any handwritten content, free photo recognition';

  @override
  String get myFonts => 'My Fonts';

  @override
  String myFontsSaved(int count) {
    return '$count font projects saved';
  }

  @override
  String get myFontsDesc => 'View and manage saved font projects';

  @override
  String get charOverview => 'Character Overview';

  @override
  String get charOverviewDesc => 'Check font progress';

  @override
  String get fontPreview => 'Font Preview';

  @override
  String get fontPreviewDesc => 'Input text to preview handwriting';

  @override
  String get enhancedPreview => 'Enhanced Preview';

  @override
  String get enhancedPreviewDesc => 'Multi-size · Multi-template · Real-time comparison';

  @override
  String get styleTransfer => 'Style Transfer';

  @override
  String get styleTransferDesc => 'AI-powered font style transformation';

  @override
  String get recommendStandard => 'Standard charset recommended for better results';

  @override
  String get justNow => 'Just now';

  @override
  String minutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String hoursAgo(int count) {
    return '$count hours ago';
  }

  @override
  String daysAgo(int count) {
    return '$count days ago';
  }

  @override
  String get onboardingWelcome => 'Create Your Font with Your Handwriting';

  @override
  String get onboardingWelcomeDesc => 'Turn your handwriting into a custom font in 3 steps';

  @override
  String get onboardingStep1 => 'Step 1';

  @override
  String get onboardingStep1Title => 'Take a Photo';

  @override
  String get onboardingStep1Desc => 'Write the specified characters on paper, then capture with your camera';

  @override
  String get onboardingStep2 => 'Step 2';

  @override
  String get onboardingStep2Title => 'Review Writing';

  @override
  String get onboardingStep2Desc => 'AI auto-recognizes each character, review and correct as needed';

  @override
  String get onboardingStep3 => 'Step 3';

  @override
  String get onboardingStep3Title => 'One-Click Generate';

  @override
  String get onboardingStep3Desc => 'AI generates 6763 common Chinese characters\nbased on your handwriting style';

  @override
  String get onboardingStartBtn => 'Start Now!';

  @override
  String get aiRecognizeAndFix => 'AI Recognition + Manual Correction';

  @override
  String get captureUpload => 'Capture';

  @override
  String get appearance => 'Appearance';

  @override
  String get recognitionSettings => 'Recognition';

  @override
  String get fontGeneration => 'Font Generation';

  @override
  String get storage => 'Storage';

  @override
  String get cloudSync => 'Cloud Sync';

  @override
  String get about => 'About';

  @override
  String get lightMode => 'Light';

  @override
  String get darkMode => 'Dark';

  @override
  String get followSystem => 'System Default';

  @override
  String appearanceChanged(String mode) {
    return 'Appearance changed to $mode';
  }

  @override
  String get language => 'Language';

  @override
  String get languageDesc => 'Change app display language';

  @override
  String get chinese => '中文';

  @override
  String get english => 'English';

  @override
  String get japanese => '日本語';

  @override
  String languageChanged(String language) {
    return 'Language changed to $language';
  }

  @override
  String get localRecognition => 'Local Recognition';

  @override
  String get localRecognitionDesc => 'Offline recognition, no network needed, free to use';

  @override
  String get cloudRecognition => 'Cloud DeepSeek-OCR';

  @override
  String get cloudRecognitionDesc => 'Higher accuracy, requires network and API Key';

  @override
  String get cloudConfig => 'Cloud Configuration';

  @override
  String get cloudConfigDesc => 'API URL, Key, Model';

  @override
  String get switchedToLocal => 'Switched to local recognition';

  @override
  String get switchedToCloud => 'Switched to cloud recognition';

  @override
  String get threshold => 'Threshold';

  @override
  String get thresholdDesc => 'Controls binarization cutoff, higher value = thicker strokes';

  @override
  String get contrast => 'Contrast';

  @override
  String get contrastDesc => 'Enhance contrast for lighter handwriting photos';

  @override
  String get smoothness => 'Smoothness';

  @override
  String get smoothnessDesc => 'Controls outline smoothness, higher = rounder strokes';

  @override
  String get strokeWidth => 'Stroke Width';

  @override
  String get strokeWidthDesc => 'Base stroke thickness for output font';

  @override
  String get paramsReset => 'Parameters reset to defaults';

  @override
  String get exportSettings => 'Export Settings';

  @override
  String get exportSettingsDesc => 'Export current settings as JSON file';

  @override
  String get importSettings => 'Import Settings';

  @override
  String get importSettingsDesc => 'Restore settings from JSON file';

  @override
  String get clearTempFiles => 'Clear Temporary Files';

  @override
  String get clearTempFilesDesc => 'Clear temp images from recognition and processing';

  @override
  String get tempFilesCleared => 'Temporary files cleared';

  @override
  String clearFailed(String error) {
    return 'Clear failed: $error';
  }

  @override
  String get settingsExported => 'Settings exported';

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get settingsImported => 'Settings imported';

  @override
  String importFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get invalidSettingsFile => 'Invalid settings file';

  @override
  String get selectSettingsFile => 'Select WriteFont settings file';

  @override
  String get settingsBackupSubject => 'WriteFont Settings Backup';

  @override
  String get settingsBackupText => 'WriteFont settings file';

  @override
  String get cloudSyncDesc => 'Multi-device sync and backup';

  @override
  String get version => 'Version';

  @override
  String get openSourceLicense => 'Open Source License';

  @override
  String get viewSourceCode => 'View Source Code';

  @override
  String get cannotOpenLink => 'Cannot open link';

  @override
  String get processing => 'Processing...';

  @override
  String get generating => 'Generating...';

  @override
  String get loading => 'Loading...';

  @override
  String get networkError => 'Network error, please check your connection';

  @override
  String get unknownError => 'Unknown error';

  @override
  String get projectList => 'Project List';

  @override
  String get fontPreviewTitle => 'Font Preview';

  @override
  String get characterEdit => 'Character Edit';

  @override
  String get captureTitle => 'Capture';

  @override
  String get batchProcessing => 'Batch Processing';

  @override
  String get ocrSettings => 'OCR Settings';

  @override
  String get writingTips => 'Writing Tips';

  @override
  String get charsetGuide => 'Charset Guide';

  @override
  String get autoGenerate => 'Auto Generate';
}
