/// 标准造字字表 - 108个常用中文字符
/// 基础30字 + 扩展78字
class StandardCharset {
  /// 基础30字（必须书写）
  static const List<StandardChar> basicChars = [
    StandardChar(char: '的', index: 1, pinyin: 'de'),
    StandardChar(char: '我', index: 2, pinyin: 'wǒ'),
    StandardChar(char: '了', index: 3, pinyin: 'le'),
    StandardChar(char: '你', index: 4, pinyin: 'nǐ'),
    StandardChar(char: '是', index: 5, pinyin: 'shì'),
    StandardChar(char: '啊', index: 6, pinyin: 'a'),
    StandardChar(char: '好', index: 7, pinyin: 'hǎo'),
    StandardChar(char: '就', index: 8, pinyin: 'jiù'),
    StandardChar(char: '吗', index: 9, pinyin: 'ma'),
    StandardChar(char: '不', index: 10, pinyin: 'bù'),
    StandardChar(char: '在', index: 11, pinyin: 'zài'),
    StandardChar(char: '有', index: 12, pinyin: 'yǒu'),
    StandardChar(char: '嗯', index: 13, pinyin: 'en'),
    StandardChar(char: '吧', index: 14, pinyin: 'ba'),
    StandardChar(char: '没', index: 15, pinyin: 'méi'),
    StandardChar(char: '去', index: 16, pinyin: 'qù'),
    StandardChar(char: '都', index: 17, pinyin: 'dōu'),
    StandardChar(char: '要', index: 18, pinyin: 'yào'),
    StandardChar(char: '那', index: 19, pinyin: 'nà'),
    StandardChar(char: '呢', index: 20, pinyin: 'ne'),
    StandardChar(char: '说', index: 21, pinyin: 'shuō'),
    StandardChar(char: '还', index: 22, pinyin: 'hái'),
    StandardChar(char: '也', index: 23, pinyin: 'yě'),
    StandardChar(char: '他', index: 24, pinyin: 'tā'),
    StandardChar(char: '哦', index: 25, pinyin: 'o'),
    StandardChar(char: '来', index: 26, pinyin: 'lái'),
    StandardChar(char: '这', index: 27, pinyin: 'zhè'),
    StandardChar(char: '给', index: 28, pinyin: 'gěi'),
    StandardChar(char: '到', index: 29, pinyin: 'dào'),
    StandardChar(char: '个', index: 30, pinyin: 'gè'),
  ];

  /// 扩展78字（覆盖高频日常用字）
  static const List<StandardChar> extendedChars = [
    // 高频虚词 & 代词
    StandardChar(char: '亲', index: 31, pinyin: 'qīn'),
    StandardChar(char: '和', index: 32, pinyin: 'hé'),
    StandardChar(char: '她', index: 33, pinyin: 'tā'),
    StandardChar(char: '们', index: 34, pinyin: 'men'),
    StandardChar(char: '很', index: 35, pinyin: 'hěn'),
    StandardChar(char: '会', index: 36, pinyin: 'huì'),
    StandardChar(char: '对', index: 37, pinyin: 'duì'),
    StandardChar(char: '着', index: 38, pinyin: 'zhe'),
    StandardChar(char: '过', index: 39, pinyin: 'guò'),
    StandardChar(char: '让', index: 40, pinyin: 'ràng'),
    StandardChar(char: '跟', index: 41, pinyin: 'gēn'),
    StandardChar(char: '被', index: 42, pinyin: 'bèi'),
    StandardChar(char: '从', index: 43, pinyin: 'cóng'),
    StandardChar(char: '比', index: 44, pinyin: 'bǐ'),
    StandardChar(char: '又', index: 45, pinyin: 'yòu'),
    StandardChar(char: '就', index: 46, pinyin: 'jiù'),
    StandardChar(char: '才', index: 47, pinyin: 'cái'),
    StandardChar(char: '只', index: 48, pinyin: 'zhǐ'),
    StandardChar(char: '已', index: 49, pinyin: 'yǐ'),
    StandardChar(char: '最', index: 50, pinyin: 'zuì'),
    // 常用动词
    StandardChar(char: '吃', index: 51, pinyin: 'chī'),
    StandardChar(char: '喝', index: 52, pinyin: 'hē'),
    StandardChar(char: '看', index: 53, pinyin: 'kàn'),
    StandardChar(char: '听', index: 54, pinyin: 'tīng'),
    StandardChar(char: '想', index: 55, pinyin: 'xiǎng'),
    StandardChar(char: '做', index: 56, pinyin: 'zuò'),
    StandardChar(char: '走', index: 57, pinyin: 'zǒu'),
    StandardChar(char: '跑', index: 58, pinyin: 'pǎo'),
    StandardChar(char: '坐', index: 59, pinyin: 'zuò'),
    StandardChar(char: '站', index: 60, pinyin: 'zhàn'),
    StandardChar(char: '拿', index: 61, pinyin: 'ná'),
    StandardChar(char: '打', index: 62, pinyin: 'dǎ'),
    StandardChar(char: '开', index: 63, pinyin: 'kāi'),
    StandardChar(char: '关', index: 64, pinyin: 'guān'),
    StandardChar(char: '写', index: 65, pinyin: 'xiě'),
    StandardChar(char: '读', index: 66, pinyin: 'dú'),
    StandardChar(char: '买', index: 67, pinyin: 'mǎi'),
    StandardChar(char: '卖', index: 68, pinyin: 'mài'),
    StandardChar(char: '用', index: 69, pinyin: 'yòng'),
    StandardChar(char: '找', index: 70, pinyin: 'zhǎo'),
    StandardChar(char: '发', index: 71, pinyin: 'fā'),
    StandardChar(char: '能', index: 72, pinyin: 'néng'),
    StandardChar(char: '把', index: 73, pinyin: 'bǎ'),
    StandardChar(char: '点', index: 74, pinyin: 'diǎn'),
    StandardChar(char: '叫', index: 75, pinyin: 'jiào'),
    StandardChar(char: '问', index: 76, pinyin: 'wèn'),
    StandardChar(char: '答', index: 77, pinyin: 'dá'),
    StandardChar(char: '知', index: 78, pinyin: 'zhī'),
    StandardChar(char: '觉', index: 79, pinyin: 'jué'),
    StandardChar(char: '得', index: 80, pinyin: 'de'),
    // 常用名词
    StandardChar(char: '人', index: 81, pinyin: 'rén'),
    StandardChar(char: '大', index: 82, pinyin: 'dà'),
    StandardChar(char: '小', index: 83, pinyin: 'xiǎo'),
    StandardChar(char: '天', index: 84, pinyin: 'tiān'),
    StandardChar(char: '水', index: 85, pinyin: 'shuǐ'),
    StandardChar(char: '火', index: 86, pinyin: 'huǒ'),
    StandardChar(char: '山', index: 87, pinyin: 'shān'),
    StandardChar(char: '家', index: 88, pinyin: 'jiā'),
    StandardChar(char: '学', index: 89, pinyin: 'xué'),
    StandardChar(char: '生', index: 90, pinyin: 'shēng'),
    StandardChar(char: '时', index: 91, pinyin: 'shí'),
    StandardChar(char: '年', index: 92, pinyin: 'nián'),
    StandardChar(char: '月', index: 93, pinyin: 'yuè'),
    StandardChar(char: '日', index: 94, pinyin: 'rì'),
    StandardChar(char: '心', index: 95, pinyin: 'xīn'),
    StandardChar(char: '手', index: 96, pinyin: 'shǒu'),
    StandardChar(char: '口', index: 97, pinyin: 'kǒu'),
    StandardChar(char: '目', index: 98, pinyin: 'mù'),
    StandardChar(char: '头', index: 99, pinyin: 'tóu'),
    StandardChar(char: '字', index: 100, pinyin: 'zì'),
    // 常用形容词 & 其他
    StandardChar(char: '多', index: 101, pinyin: 'duō'),
    StandardChar(char: '少', index: 102, pinyin: 'shǎo'),
    StandardChar(char: '长', index: 103, pinyin: 'cháng'),
    StandardChar(char: '高', index: 104, pinyin: 'gāo'),
    StandardChar(char: '新', index: 105, pinyin: 'xīn'),
    StandardChar(char: '老', index: 106, pinyin: 'lǎo'),
    StandardChar(char: '后', index: 107, pinyin: 'hòu'),
    StandardChar(char: '前', index: 108, pinyin: 'qián'),
  ];

  /// 获取全部108字
  static List<StandardChar> get allChars => [...basicChars, ...extendedChars];

  /// 获取所有字符字符串
  static List<String> get allCharStrings => allChars.map((c) => c.char).toList();

  /// 根据字符查找
  static StandardChar? findChar(String char) {
    try {
      return allChars.firstWhere((c) => c.char == char);
    } catch (e) {
      return null;
    }
  }
}

/// 标准字符数据类
class StandardChar {
  final String char;
  final int index;
  final String pinyin;

  const StandardChar({
    required this.char,
    required this.index,
    required this.pinyin,
  });
}
