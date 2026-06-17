/// 标准造字字表 - 40个常用中文字符
/// 基础30字 + 扩展10字
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

  /// 扩展10字（可选，写得越多越像）
  static const List<StandardChar> extendedChars = [
    StandardChar(char: '亲', index: 31, pinyin: 'qīn'),
    StandardChar(char: '和', index: 32, pinyin: 'hé'),
    StandardChar(char: '吃', index: 33, pinyin: 'chī'),
    StandardChar(char: '点', index: 34, pinyin: 'diǎn'),
    StandardChar(char: '她', index: 35, pinyin: 'tā'),
    StandardChar(char: '想', index: 36, pinyin: 'xiǎng'),
    StandardChar(char: '发', index: 37, pinyin: 'fā'),
    StandardChar(char: '能', index: 38, pinyin: 'néng'),
    StandardChar(char: '把', index: 39, pinyin: 'bǎ'),
    StandardChar(char: '买', index: 40, pinyin: 'mǎi'),
  ];

  /// 获取全部40字
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
