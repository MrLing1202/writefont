import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => '手迹造字';

  @override
  String get appTitle => '手迹造字 WriteFont';

  @override
  String get settings => '设置';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确认';

  @override
  String get close => '关闭';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String get retry => '重试';

  @override
  String get back => '返回';

  @override
  String get start => '开始';

  @override
  String get done => '完成';

  @override
  String get skip => '跳过';

  @override
  String get nextStep => '下一步';

  @override
  String get prevStep => '上一步';

  @override
  String get resetToDefault => '重置为默认值';

  @override
  String get welcomeToApp => '欢迎使用手迹造字';

  @override
  String get welcomeSubtitle => '拍照生成你的专属手写字体';

  @override
  String get createdProjects => '已创建项目';

  @override
  String get recognizedChars => '已识别字符';

  @override
  String get recentActivity => '最近活动';

  @override
  String get oneClickGenerate => '一键生成';

  @override
  String get oneClickGenerateDesc => '拍照即生成，全自动无需手动操作';

  @override
  String get standardCharset => '标准字表造字';

  @override
  String get standardCharsetDesc => '按40个常用字书写，AI自动识别匹配';

  @override
  String get quickExperience => '快速体验';

  @override
  String get quickExperienceDesc => '只需写10个字，快速体验造字';

  @override
  String get freeCapture => '自由拍照造字';

  @override
  String get freeCaptureDesc => '任意手写内容，自由拍照识别';

  @override
  String get myFonts => '我的字体';

  @override
  String myFontsSaved(int count) {
    return '已保存 $count 个字体项目';
  }

  @override
  String get myFontsDesc => '查看和管理已保存的字体项目';

  @override
  String get charOverview => '字符总览';

  @override
  String get charOverviewDesc => '查看造字进度';

  @override
  String get fontPreview => '字体预览';

  @override
  String get fontPreviewDesc => '输入文字查看手迹效果';

  @override
  String get enhancedPreview => '增强预览';

  @override
  String get enhancedPreviewDesc => '多字号 · 多场景 · 实时对比';

  @override
  String get styleTransfer => '风格迁移';

  @override
  String get styleTransferDesc => 'AI 智能字体风格转换';

  @override
  String get recommendStandard => '推荐使用标准字表，生成效果更好';

  @override
  String get justNow => '刚刚';

  @override
  String minutesAgo(int count) {
    return '$count 分钟前';
  }

  @override
  String hoursAgo(int count) {
    return '$count 小时前';
  }

  @override
  String daysAgo(int count) {
    return '$count 天前';
  }

  @override
  String get onboardingWelcome => '用你的笔迹，创造你的字体';

  @override
  String get onboardingWelcomeDesc => '只需3步，把你的手写变成专属字体';

  @override
  String get onboardingStep1 => '第1步';

  @override
  String get onboardingStep1Title => '拍照上传';

  @override
  String get onboardingStep1Desc => '在纸上写下指定的汉字，用手机拍下手写字迹';

  @override
  String get onboardingStep2 => '第2步';

  @override
  String get onboardingStep2Title => '检查书写';

  @override
  String get onboardingStep2Desc => 'AI自动识别每个字符，检查并修正不准确的地方';

  @override
  String get onboardingStep3 => '第3步';

  @override
  String get onboardingStep3Title => '一键生成';

  @override
  String get onboardingStep3Desc => 'AI根据你的笔迹风格，\n自动生成6763个常用汉字';

  @override
  String get onboardingStartBtn => '立即开始造字！';

  @override
  String get aiRecognizeAndFix => 'AI识别 + 手动修正';

  @override
  String get captureUpload => '拍照上传';

  @override
  String get appearance => '外观';

  @override
  String get recognitionSettings => '识别设置';

  @override
  String get fontGeneration => '字体生成';

  @override
  String get storage => '存储';

  @override
  String get cloudSync => '云同步';

  @override
  String get about => '关于';

  @override
  String get lightMode => '浅色';

  @override
  String get darkMode => '深色';

  @override
  String get followSystem => '跟随系统';

  @override
  String appearanceChanged(String mode) {
    return '外观已切换为$mode';
  }

  @override
  String get language => '语言';

  @override
  String get languageDesc => '切换应用显示语言';

  @override
  String get chinese => '中文';

  @override
  String get english => 'English';

  @override
  String get japanese => '日本語';

  @override
  String languageChanged(String language) {
    return '语言已切换为$language';
  }

  @override
  String get localRecognition => '本地识别';

  @override
  String get localRecognitionDesc => '离线识别，无需网络，免费使用';

  @override
  String get cloudRecognition => '云端 DeepSeek-OCR';

  @override
  String get cloudRecognitionDesc => '更高精度，需要网络和 API Key';

  @override
  String get cloudConfig => '云端配置';

  @override
  String get cloudConfigDesc => 'API 地址、Key、模型';

  @override
  String get switchedToLocal => '已切换到本地识别';

  @override
  String get switchedToCloud => '已切换到云端识别';

  @override
  String get threshold => '阈值';

  @override
  String get thresholdDesc => '控制二值化分割点，值越大笔画越粗';

  @override
  String get contrast => '对比度';

  @override
  String get contrastDesc => '增强手写图片对比度，照片较淡时增大此值';

  @override
  String get smoothness => '平滑度';

  @override
  String get smoothnessDesc => '控制轮廓平滑程度，值越大笔画越圆润';

  @override
  String get strokeWidth => '笔画宽度';

  @override
  String get strokeWidthDesc => '输出字体的基础笔画粗细';

  @override
  String get paramsReset => '参数已重置为默认值';

  @override
  String get exportSettings => '导出设置';

  @override
  String get exportSettingsDesc => '将当前设置导出为 JSON 文件';

  @override
  String get importSettings => '导入设置';

  @override
  String get importSettingsDesc => '从 JSON 文件恢复设置';

  @override
  String get clearTempFiles => '清除临时文件';

  @override
  String get clearTempFilesDesc => '清除识别和处理过程中产生的临时图片';

  @override
  String get tempFilesCleared => '临时文件已清除';

  @override
  String clearFailed(String error) {
    return '清除失败: $error';
  }

  @override
  String get settingsExported => '设置已导出';

  @override
  String exportFailed(String error) {
    return '导出失败: $error';
  }

  @override
  String get settingsImported => '设置已导入';

  @override
  String importFailed(String error) {
    return '导入失败: $error';
  }

  @override
  String get invalidSettingsFile => '无效的设置文件';

  @override
  String get selectSettingsFile => '选择 WriteFont 设置文件';

  @override
  String get settingsBackupSubject => 'WriteFont 设置备份';

  @override
  String get settingsBackupText => 'WriteFont 设置文件';

  @override
  String get cloudSyncDesc => '多设备同步和备份';

  @override
  String get version => '版本';

  @override
  String get openSourceLicense => '开源协议';

  @override
  String get viewSourceCode => '查看源代码';

  @override
  String get cannotOpenLink => '无法打开链接';

  @override
  String get processing => '处理中...';

  @override
  String get generating => '生成中...';

  @override
  String get loading => '加载中...';

  @override
  String get networkError => '网络错误，请检查网络连接';

  @override
  String get unknownError => '未知错误';

  @override
  String get projectList => '项目列表';

  @override
  String get fontPreviewTitle => '字体预览';

  @override
  String get characterEdit => '字符编辑';

  @override
  String get captureTitle => '拍照';

  @override
  String get batchProcessing => '批量处理';

  @override
  String get ocrSettings => 'OCR 设置';

  @override
  String get writingTips => '书写提示';

  @override
  String get charsetGuide => '字表指南';

  @override
  String get autoGenerate => '自动识别';
}
