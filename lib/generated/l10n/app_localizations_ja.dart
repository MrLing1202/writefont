import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appName => 'WriteFont';

  @override
  String get appTitle => 'WriteFont - 手書きフォントメーカー';

  @override
  String get settings => '設定';

  @override
  String get cancel => 'キャンセル';

  @override
  String get confirm => '確認';

  @override
  String get close => '閉じる';

  @override
  String get save => '保存';

  @override
  String get delete => '削除';

  @override
  String get retry => '再試行';

  @override
  String get back => '戻る';

  @override
  String get start => '開始';

  @override
  String get done => '完了';

  @override
  String get skip => 'スキップ';

  @override
  String get nextStep => '次へ';

  @override
  String get prevStep => '戻る';

  @override
  String get resetToDefault => 'デフォルトに戻す';

  @override
  String get welcomeToApp => 'WriteFontへようこそ';

  @override
  String get welcomeSubtitle => 'あなたの手書きをフォントに';

  @override
  String get createdProjects => 'プロジェクト';

  @override
  String get recognizedChars => '文字数';

  @override
  String get recentActivity => '最近の活動';

  @override
  String get oneClickGenerate => 'ワンクリック生成';

  @override
  String get oneClickGenerateDesc => '写真を撮るだけで全自動で生成';

  @override
  String get standardCharset => '標準文字表';

  @override
  String get standardCharsetDesc => '40個の常用漢字を書く、AI自動認識';

  @override
  String get quickExperience => 'クイック体験';

  @override
  String get quickExperienceDesc => 'わずか10文字で造字を体験';

  @override
  String get freeCapture => '自由撮影';

  @override
  String get freeCaptureDesc => '任意の手書き内容を自由に撮影認識';

  @override
  String get myFonts => 'マイフォント';

  @override
  String myFontsSaved(int count) {
    return '$count件のフォントプロジェクト';
  }

  @override
  String get myFontsDesc => '保存済みフォントの管理';

  @override
  String get charOverview => '文字一覧';

  @override
  String get charOverviewDesc => '造字の進捗を確認';

  @override
  String get fontPreview => 'フォントプレビュー';

  @override
  String get fontPreviewDesc => 'テキストを入力して手書き効果を確認';

  @override
  String get enhancedPreview => '拡張プレビュー';

  @override
  String get enhancedPreviewDesc => '複数サイズ・複数テンプレート・リアルタイム比較';

  @override
  String get styleTransfer => 'スタイル転写';

  @override
  String get styleTransferDesc => 'AI搭載フォントスタイル変換';

  @override
  String get recommendStandard => '標準文字表の使用で、より良い結果が得られます';

  @override
  String get justNow => 'たった今';

  @override
  String minutesAgo(int count) {
    return '$count分前';
  }

  @override
  String hoursAgo(int count) {
    return '$count時間前';
  }

  @override
  String daysAgo(int count) {
    return '$count日前';
  }

  @override
  String get onboardingWelcome => 'あなたの筆跡で、オリジナルフォントを';

  @override
  String get onboardingWelcomeDesc => 'たった3ステップで手書きフォントを作成';

  @override
  String get onboardingStep1 => 'ステップ1';

  @override
  String get onboardingStep1Title => '写真を撮る';

  @override
  String get onboardingStep1Desc => '紙に指定の漢字を書き、カメラで撮影';

  @override
  String get onboardingStep2 => 'ステップ2';

  @override
  String get onboardingStep2Title => '書き方を確認';

  @override
  String get onboardingStep2Desc => 'AIが各文字を自動認識、不正確な部分を修正';

  @override
  String get onboardingStep3 => 'ステップ3';

  @override
  String get onboardingStep3Title => 'ワンクリック生成';

  @override
  String get onboardingStep3Desc => 'あなたの筆跡スタイルに基づいて\nAIが6763個の常用漢字を自動生成';

  @override
  String get onboardingStartBtn => '今すぐ開始！';

  @override
  String get aiRecognizeAndFix => 'AI認識 + 手動修正';

  @override
  String get captureUpload => '撮影';

  @override
  String get appearance => '外観';

  @override
  String get recognitionSettings => '認識設定';

  @override
  String get fontGeneration => 'フォント生成';

  @override
  String get storage => 'ストレージ';

  @override
  String get cloudSync => 'クラウド同期';

  @override
  String get about => 'アプリについて';

  @override
  String get lightMode => 'ライト';

  @override
  String get darkMode => 'ダーク';

  @override
  String get followSystem => 'システム設定に従う';

  @override
  String appearanceChanged(String mode) {
    return '外観を$modeに変更しました';
  }

  @override
  String get language => '言語';

  @override
  String get languageDesc => 'アプリの表示言語を切り替え';

  @override
  String get chinese => '中文';

  @override
  String get english => 'English';

  @override
  String get japanese => '日本語';

  @override
  String languageChanged(String language) {
    return '言語を$languageに変更しました';
  }

  @override
  String get localRecognition => 'ローカル認識';

  @override
  String get localRecognitionDesc => 'オフライン認識、ネットワーク不要、無料';

  @override
  String get cloudRecognition => 'クラウド DeepSeek-OCR';

  @override
  String get cloudRecognitionDesc => '高精度、ネットワークとAPIキーが必要';

  @override
  String get cloudConfig => 'クラウド設定';

  @override
  String get cloudConfigDesc => 'API URL、キー、モデル';

  @override
  String get switchedToLocal => 'ローカル認識に切り替えました';

  @override
  String get switchedToCloud => 'クラウド認識に切り替えました';

  @override
  String get threshold => '閾値';

  @override
  String get thresholdDesc => '二値化の分岐点を制御、値が大きいほど太い';

  @override
  String get contrast => 'コントラスト';

  @override
  String get contrastDesc => '手書き画像のコントラストを強化';

  @override
  String get smoothness => 'スムーズネス';

  @override
  String get smoothnessDesc => '輪郭の滑らかさを制御、値が大きいほど丸い';

  @override
  String get strokeWidth => '線の太さ';

  @override
  String get strokeWidthDesc => '出力フォントの基本線の太さ';

  @override
  String get paramsReset => 'パラメータをデフォルトに戻しました';

  @override
  String get exportSettings => '設定のエクスポート';

  @override
  String get exportSettingsDesc => '現在の設定をJSONファイルとしてエクスポート';

  @override
  String get importSettings => '設定のインポート';

  @override
  String get importSettingsDesc => 'JSONファイルから設定を復元';

  @override
  String get clearTempFiles => '一時ファイルの削除';

  @override
  String get clearTempFilesDesc => '認識・処理で生成された一時画像を削除';

  @override
  String get tempFilesCleared => '一時ファイルを削除しました';

  @override
  String clearFailed(String error) {
    return '削除失敗: $error';
  }

  @override
  String get settingsExported => '設定をエクスポートしました';

  @override
  String exportFailed(String error) {
    return 'エクスポート失敗: $error';
  }

  @override
  String get settingsImported => '設定をインポートしました';

  @override
  String importFailed(String error) {
    return 'インポート失敗: $error';
  }

  @override
  String get invalidSettingsFile => '無効な設定ファイル';

  @override
  String get selectSettingsFile => 'WriteFont設定ファイルを選択';

  @override
  String get settingsBackupSubject => 'WriteFont設定バックアップ';

  @override
  String get settingsBackupText => 'WriteFont設定ファイル';

  @override
  String get cloudSyncDesc => 'マルチデバイス同期とバックアップ';

  @override
  String get version => 'バージョン';

  @override
  String get openSourceLicense => 'オープンソースライセンス';

  @override
  String get viewSourceCode => 'ソースコードを見る';

  @override
  String get cannotOpenLink => 'リンクを開けません';

  @override
  String get processing => '処理中...';

  @override
  String get generating => '生成中...';

  @override
  String get loading => '読み込み中...';

  @override
  String get networkError => 'ネットワークエラー、接続を確認してください';

  @override
  String get unknownError => '不明なエラー';

  @override
  String get projectList => 'プロジェクト一覧';

  @override
  String get fontPreviewTitle => 'フォントプレビュー';

  @override
  String get characterEdit => '文字編集';

  @override
  String get captureTitle => '撮影';

  @override
  String get batchProcessing => 'バッチ処理';

  @override
  String get ocrSettings => 'OCR設定';

  @override
  String get writingTips => '書き方のヒント';

  @override
  String get charsetGuide => '文字表ガイド';

  @override
  String get autoGenerate => '自動認識';
}
