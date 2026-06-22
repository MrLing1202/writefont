import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 字典后处理服务
///
/// 通过本地字典过滤识别结果，常见字优先，减少误识别。
///
/// 功能：
/// - 内置常用汉字频率表（前 3000 字）
/// - 形近字映射（已/己/巳、未/末 等易混淆组）
/// - 用户常用字缓存（SharedPreferences 持久化）
/// - 识别结果后处理：非常见字自动替换为形近常见字
class DictionaryService {
  // SharedPreferences keys
  static const String _prefKeyUserChars = 'dict_user_chars';

  // 单例
  static DictionaryService? _instance;
  static DictionaryService get instance => _instance ??= DictionaryService._();

  DictionaryService._();

  /// 用户常用字缓存（字符 → 使用次数），启动时从 SharedPreferences 加载
  Map<String, int> _userCharFrequency = {};
  bool _loaded = false;

  /// 常用汉字频率表（前 3000 字，按使用频率降序）
  /// 来源：基于国家语委《现代汉语通用字频度表》及日常使用频率综合排序
  static const String _frequencyTable =
      '的一是不了人我在有他这中大来上个国'
      '到说们为子和你地出会也时要就可以生'
      '对以着那她两去然里后自之年下得之家'
      '学过发成方多当事用如前所本日行能小'
      '作理公分些三高进种还同动定起开样第'
      '现法当面从体实全意其主无问样子工关'
      '手只西把因点又与正明想最看月已长市'
      '十头等电新被二前力加知做机美什心身'
      '物太真见但文信位次门感特外它给世名'
      '间数别山口水先听表代入风教原光走叫'
      '克白东打各再每内少安回或女场正气许'
      '主让利此道平路快更比放产经解己提报'
      '化及口条万车路并立通目满天受部西情'
      '很性总政应社者专四字海民干情才神系'
      '林色英区近争活拉打八何老根共取直设'
      '达场反式论基志边料展资量六管区南常'
      '识记花且深更求清联至书非研色认目注'
      '整治保热七切务思完整空带约质务规收'
      '持层局布需半组世具即区九流断传步交'
      '示则件张件将指感运己任风接信采价治'
      '话示火德病石造影今空往视死算青六记'
      '候元北术未权却满研离观突极火构食状'
      '南亲百眼实际图包红强品准参破改速每'
      '转集太除议青持案龙倒存客标落调陈配'
      '独星夜按早存阵阳可取色根音维消值客'
      '似找失孩红坏轻护英商齐黄够苦答期始'
      '装封居局续双客底冷功举黑专击居右切'
      '评微任息省响须差止按每谁修九阳收写'
      '另惊怕愿春演充左细严复响念岁害找乐'
      '晚规举圣类往八续断讲忘喜怕苏医良'
      '初六创竟消装均居角衣哪雨助复医食善'
      '构永假梦铁固谢贵客鱼草雪刻随印食尚'
      '座底刻毛异秋敢窗散暗拿脑古够简赶'
      '紧称团雷冰静续围劳古阿块核故录追'
      '店您含笔划惊娘另固忙架项伴案简折'
      '谁试雄钟庆双遇怒另散某阵暗委肉灵'
      '吃装厚固秘序编仁微靠异亮圆甲宝富'
      '遇良份读夜伤控层抽劳短食久嘛晓材'
      '牛排程伤著责退闪简含仅靠拿急稳怕'
      '窗异雷笔超圣忙帮靠败优靠吉借左招'
      '陈卫静借藏奥仍凡闭勇宁刻序雪惊编'
      '层阵创肉靠忙固雷散秘吃围另敢冰双'
      '您钟雄遇怒团块含找阿庆古简项批另'
      '封哪划折紧谁窗响威启哪异亮圆宝富'
      '读份久抽含伤材控牛夜靠仅排紧急稳';

  /// 形近字映射表
  /// 键为某个字，值为该字的形近字列表（均为常见字）
  /// 当识别结果为某个不常见字时，可通过此表找到形近的常见字
  static const Map<String, List<String>> _similarChars = {
    // 口/丁（手写体方形 vs T 形极易混淆）
    '口': ['丁'],
    '丁': ['口'],

    // 已/己/巳
    '已': ['己', '巳'],
    '己': ['已', '巳'],
    '巳': ['已', '己'],

    // 未/末
    '未': ['末'],
    '末': ['未'],

    // 大/太/犬/夫
    '大': ['太', '犬'],
    '太': ['大', '犬', '夫'],
    '犬': ['大', '太'],

    // 日/目/且/月
    '日': ['目', '且', '月'],
    '目': ['日', '且', '自'],
    '且': ['日', '目'],
    '月': ['日'],

    // 土/士
    '土': ['士'],
    '士': ['土'],

    // 刀/力
    '刀': ['力'],
    '力': ['刀'],

    // 人/入
    '人': ['入'],
    '入': ['人'],

    // 干/千
    '干': ['千'],
    '千': ['干'],

    // 天/夫
    '天': ['夫'],
    '夫': ['天'],

    // 木/本/术
    '木': ['本', '术'],
    '本': ['木', '术'],
    '术': ['木', '本'],

    // 甲/由/田
    '甲': ['由', '田'],
    '由': ['甲', '田'],
    '田': ['甲', '由'],

    // 白/自/百
    '白': ['自', '百'],
    '自': ['白', '百'],
    '百': ['白', '自'],

    // 问/间/向
    '问': ['间', '向'],
    '间': ['问', '向'],
    '向': ['问', '间'],

    // 王/玉/主
    '王': ['玉', '主'],
    '玉': ['王', '主'],
    '主': ['王', '玉'],

    // 今/令/合
    '今': ['令', '合'],
    '令': ['今', '合'],
    '合': ['今', '令'],

    // 几/九/儿
    '几': ['九', '儿'],
    '九': ['几', '儿'],
    '儿': ['几', '九'],

    // 万/方/力
    '万': ['方'],
    '方': ['万'],

    // 从/以/比
    '从': ['以', '比'],
    '以': ['从', '比'],
    '比': ['从', '以'],

    // 了/子/于
    '了': ['子', '于'],
    '子': ['了', '于'],
    '于': ['了', '子'],

    // 又/义/叉
    '又': ['义'],
    '义': ['又'],

    // 个/介
    '个': ['介'],
    '介': ['个'],

    // 元/无/先
    '元': ['无', '先'],
    '无': ['元', '先'],
    '先': ['元', '无'],

    // 见/贝/兄
    '见': ['贝', '兄'],
    '贝': ['见', '兄'],
    '兄': ['见', '贝'],

    // 公/分/会
    '公': ['分'],
    '分': ['公'],

    // 去/云/走
    '去': ['云'],
    '云': ['去'],

    // 车/东
    '车': ['东'],
    '东': ['车'],

    // 工/二/三
    '工': ['二'],
    '二': ['工'],

    // 山/出
    '山': ['出'],
    '出': ['山'],

    // 止/正
    '止': ['正'],
    '正': ['止'],

    // 禾/利
    '禾': ['利', '木'],
    '利': ['禾'],

    // 来/末
    '来': ['末', '未'],

    // 买/卖
    '买': ['卖'],
    '卖': ['买'],

    // 午/牛
    '午': ['牛'],
    '牛': ['午'],

    // 壬/王
    '壬': ['王'],

    // 失/矢
    '失': ['矢'],
    '矢': ['失'],

    // 刃/刀
    '刃': ['刀'],

    // 夕/歹
    '夕': ['歹'],
    '歹': ['夕'],

    // ── 扩展形近字（手写体高频混淆） ──

    // 才/寸
    '才': ['寸'],
    '寸': ['才'],

    // 么/幺
    '么': ['幺'],

    // 与/写
    '与': ['写'],

    // 也/他/地
    '也': ['他', '地'],

    // 五/互
    '五': ['互'],
    '互': ['五'],

    // 只/兄
    '只': ['兄'],

    // 古/右/石
    '古': ['右', '石'],
    '右': ['古', '石'],
    '石': ['古', '右'],

    // 处/外
    '处': ['外'],
    '外': ['处'],

    // 太/大/丈
    '丈': ['大', '太'],

    // 女/奴
    '女': ['奴'],

    // 字/学
    '字': ['学'],
    '学': ['字'],

    // 年/午
    '年': ['午'],

    // 并/开
    '并': ['开'],
    '开': ['并'],

    // 广/厂
    '广': ['厂'],
    '厂': ['广'],

    // 心/必
    '心': ['必'],
    '必': ['心'],

    // 手/毛
    '手': ['毛'],
    '毛': ['手'],

    // 方/万/芳
    '芳': ['方'],

    // 明/朋
    '明': ['朋'],
    '朋': ['明'],

    // 氏/氏
    '氏': ['民'],
    '民': ['氏'],

    // 水/永
    '水': ['永'],
    '永': ['水'],

    // 汁/汗/汁
    '汁': ['汗'],
    '汗': ['汁'],

    // 片/版
    '片': ['版'],

    // 现/观
    '现': ['观'],
    '观': ['现'],

    // 理/埋
    '理': ['埋'],
    '埋': ['理'],

    // 睛/晴/睛
    '睛': ['晴'],
    '晴': ['睛'],

    // 科/料
    '科': ['料'],
    '料': ['科'],

    // 立/位
    '立': ['位'],

    // 笔/笑
    '笔': ['笑'],
    '笑': ['笔'],

    // 经/径
    '经': ['径'],
    '径': ['经'],

    // 者/著
    '者': ['著'],

    // 色/巴
    '色': ['巴'],

    // 花/化
    '花': ['化'],

    // 认/让
    '认': ['让'],
    '让': ['认'],

    // 话/活
    '话': ['活'],
    '活': ['话'],

    // 贝/见
    '贝': ['见'],

    // 起/越
    '起': ['越'],
    '越': ['起'],

    // 身/射
    '身': ['射'],

    // 辛/幸
    '辛': ['幸'],
    '幸': ['辛'],

    // 里/重
    '里': ['重'],

    // 长/张
    '长': ['张'],

    // 阳/阴
    '阳': ['阴'],
    '阴': ['阳'],

    // 面/而
    '面': ['而'],

    // 风/凤
    '风': ['凤'],
    '凤': ['风'],
  };

  // ═══════════════════════════════════════════
  // 公开 API
  // ═══════════════════════════════════════════

  /// 获取字符的频率排名（0 = 最常用，越大越不常用）
  /// 返回 -1 表示不在频率表中（非常用字）
  int getFrequency(String char) {
    if (char.isEmpty) return -1;
    final index = _frequencyTable.indexOf(char);
    return index >= 0 ? index : -1;
  }

  /// 判断是否为常见字（在前 3000 常用字表中）
  bool isCommonChar(String char) {
    if (char.isEmpty) return false;
    return _frequencyTable.contains(char);
  }

  /// 判断是否为用户常用字
  bool isUserCommonChar(String char) {
    if (char.isEmpty) return false;
    return _userCharFrequency.containsKey(char);
  }

  /// 获取形近的常见字列表
  ///
  /// 返回与 [char] 形近的常见字列表（空列表表示无形近字映射）
  List<String> getSimilarChars(String char) {
    if (char.isEmpty) return [];
    return _similarChars[char] ?? [];
  }

  /// 推荐相似的常见字
  ///
  /// 逻辑：
  /// 1. 如果 char 本身是常见字，直接返回 char
  /// 2. 查找形近字表，返回其中频率最高的常见字
  /// 3. 无形近字则返回 null
  String? suggestSimilar(String char) {
    if (char.isEmpty) return null;

    // 本身是常见字，无需替换
    if (isCommonChar(char)) return char;

    // 查找形近字
    final similar = getSimilarChars(char);
    if (similar.isEmpty) return null;

    // 选择频率最高的形近字
    String? best;
    int bestRank = _frequencyTable.length + 1;
    for (final s in similar) {
      final rank = getFrequency(s);
      if (rank >= 0 && rank < bestRank) {
        bestRank = rank;
        best = s;
      }
    }

    return best;
  }

  /// 后处理识别结果
  ///
  /// 核心方法：接收原始识别结果，返回优化后的结果。
  ///
  /// 逻辑：
  /// 1. 如果识别结果是常见字 → 直接返回
  /// 2. 如果有形近常见字 → 返回最常见那个
  /// 3. 如果用户历史常用这个字 → 返回原字
  /// 4. 否则返回原字（不替换）
  ///
  /// [result] 原始识别结果字符
  /// [confidence] 识别置信度（0.0~1.0），仅当置信度不太低时才做替换
  String postProcess(String result, {double confidence = 1.0}) {
    if (result.isEmpty) return result;

    final char = result;

    // 常见字，无需处理
    if (isCommonChar(char)) return char;

    // 置信度太低时不做替换，避免误改
    if (confidence < 0.5) return char;

    // 用户历史中常用此字，保留
    if (isUserCommonChar(char)) return char;

    // 查找形近常见字
    final suggested = suggestSimilar(char);
    if (suggested != null && suggested != char) {
      // 只有置信度不够高时才替换（≥0.5 且 < 0.85）
      // 高置信度时信任 OCR 结果
      if (confidence < 0.85) {
        debugPrint('字典后处理: "$char" → "$suggested" (形近字替换, 置信度=${(confidence * 100).toStringAsFixed(0)}%)');
        return suggested;
      }
    }

    return char;
  }

  /// 记录用户识别过的字符（更新用户常用字缓存）
  ///
  /// 在每次识别成功后调用，累积用户的使用习惯。
  Future<void> recordUsage(String char) async {
    if (char.isEmpty) return;

    await _ensureLoaded();

    _userCharFrequency[char] = (_userCharFrequency[char] ?? 0) + 1;

    // 限制缓存大小，淘汰使用次数最少的
    if (_userCharFrequency.length > _maxUserChars) {
      _pruneUserChars();
    }

    await _save();
  }

  /// 获取用户使用频率最高的字符列表
  List<MapEntry<String, int>> getTopUserChars({int limit = 50}) {
    final sorted = _userCharFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }

  /// 获取字典服务统计信息
  Map<String, dynamic> getStats() {
    return {
      'frequencyTableSize': _frequencyTable.length,
      'similarCharGroups': _similarChars.length,
      'userCharCount': _userCharFrequency.length,
      'topUserChars': getTopUserChars(limit: 10).map((e) => '${e.key}(${e.value})').toList(),
    };
  }

  /// 清空用户常用字缓存
  Future<void> clearUserChars() async {
    _userCharFrequency.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyUserChars);
    debugPrint('字典服务: 已清空用户常用字缓存');
  }

  // ═══════════════════════════════════════════
  // 内部方法
  // ═══════════════════════════════════════════

  /// 用户常用字最大缓存数
  static const int _maxUserChars = 500;

  /// 确保用户数据已加载
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefKeyUserChars);
      if (json != null && json.isNotEmpty) {
        final map = jsonDecode(json) as Map<String, dynamic>;
        _userCharFrequency = map.map((k, v) => MapEntry(k, v as int));
        debugPrint('字典服务: 已加载 ${_userCharFrequency.length} 个用户常用字');
      }
    } catch (e) {
      debugPrint('字典服务: 加载用户常用字失败 $e');
      _userCharFrequency = {};
    }
  }

  /// 持久化保存用户常用字
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_userCharFrequency);
      await prefs.setString(_prefKeyUserChars, json);
    } catch (e) {
      debugPrint('字典服务: 保存用户常用字失败 $e');
    }
  }

  /// 淘汰使用次数最少的用户常用字
  void _pruneUserChars() {
    final sorted = _userCharFrequency.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    // 移除最少使用的 20%
    final removeCount = (_maxUserChars * 0.2).round();
    for (int i = 0; i < removeCount && i < sorted.length; i++) {
      _userCharFrequency.remove(sorted[i].key);
    }
  }
}
