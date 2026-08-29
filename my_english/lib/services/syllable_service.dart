// ============================================================================
//  业务服务层：在"纯算法"之上叠加 App 需要的逻辑
// ============================================================================
//  核心算法（liang_algorithm.dart）只负责"算"，本层负责"用"：
//    · split            —— 算出最细切法；
//    · nextAlternative  —— 换一种合规切法（确定、有限、不随机）。
//
//  2.0 起本服务是**纯计算**的，自己不碰数据库：音节拆分现在住在单词行的
//  `syllables` 字段里，由页面在需要时调用 WordStore.saveWordSyllables 落库。
//  这样音节不再有自己的表，服务也不必再为「存哪、什么时候存」负责。
// ============================================================================

import 'liang_algorithm.dart';

/// 音节切分服务（对外主入口）。
///
/// 用法：
///   final service = SyllableService();
///   final parts = service.split('tradition'); // ["tradi", "tion"]
class SyllableService {
  // 纯算法核心；允许从外部传入，方便测试时注入同一个实例。
  final LiangHyphenator _hyphenator;

  SyllableService([LiangHyphenator? hyphenator])
    : _hyphenator = hyphenator ?? LiangHyphenator();

  /// 算出一个单词的「最细音节划分」。
  ///
  /// 空词原样返回，保证调用方拿到的永远是非空列表。
  List<String> split(String word) {
    // 保留原始大小写用于展示；规则表查的是小写。
    final display = word.trim();
    if (display.isEmpty) return <String>[word];
    return _hyphenator.split(display);
  }

  /// 刷新：从 [current] 换到下一种"合规但不随机"的切法。
  ///
  /// 规则（确定且有限）：算法先给出全部合法断点；从最细切法开始，
  /// 每次合并"最弱的一个断点"变粗，直到整词；到头后再回到最细，循环。
  ///
  /// [splitOnly] 为 true 时把"整词"这一档从循环里剔除，只在真正拆得开的切法
  /// 之间轮换。拼写巩固的片段模式必须这样用：整词那一档只会生成一个候选按钮，
  /// 点一下就过关，等于把题目送掉。若该词一种能拆开的切法都没有（如 bowl），
  /// 则原样返回 [current]，调用方据此让它留在逐字母模式。
  List<String> nextAlternative(
    String word, {
    required List<String> current,
    bool splitOnly = false,
  }) {
    final display = word.trim();
    if (display.isEmpty) return <String>[word];
    final alts = _splitOnlyFiltered(_alternatives(display), splitOnly);
    // 一种能拆开的切法都没有：保持现状，让调用方留在逐字母模式。
    if (alts.isEmpty) return current.isEmpty ? <String>[display] : current;
    // 找到当前是第几个备选；找不到就当成最细(0)，跳到下一个。
    var index = -1;
    if (current.isNotEmpty) {
      // 用普通字符做整体比较，避免逐段比对时的下标越界。
      final joined = current.join('|');
      for (var i = 0; i < alts.length; i += 1) {
        if (alts[i].join('|') == joined) {
          index = i;
          break;
        }
      }
    }
    // 循环：最后一档之后回到最细。
    return alts[(index + 1) % alts.length];
  }

  // ----- 以下为内部实现 -----

  /// 按需剔除"整词"那一档备选。
  ///
  /// [splitOnly] 为 false 时原样返回，保持既有调用方行为不变。
  List<List<String>> _splitOnlyFiltered(
    List<List<String>> alts,
    bool splitOnly,
  ) {
    if (!splitOnly) return alts;
    return [
      for (final alt in alts)
        if (alt.length > 1) alt,
    ];
  }

  /// 生成该词的"全部备选切法"，从最细到最粗（最后一个是整词）。
  ///
  /// 例如 tradition 的断点只有 1 个，则备选只有 [最细, 整词] 两种。
  /// banana 有 2 个断点，则有 [最细, 去掉弱断点, 整词] 三种。
  List<List<String>> _alternatives(String word) {
    // 规则表查的是小写词，但切分展示用原始大小写（长度一致，下标可直接套用）。
    final breaks = _hyphenator.breakPositions(word);
    // 移除顺序：先并最弱的（strength 小），同级按位置升序，确定不随机。
    final removalOrder = List<HyphenBreak>.from(breaks)
      ..sort(
        (a, b) => a.strength != b.strength
            ? a.strength.compareTo(b.strength)
            : a.position.compareTo(b.position),
      );
    final alts = <List<String>>[];
    // alts[0] = 全部断点（最细）
    final allPositions = breaks.map((b) => b.position).toList()..sort();
    alts.add(_splitAt(word, allPositions));
    // 逐步去掉最弱断点，得到越来越粗的切法。
    for (var k = 1; k <= removalOrder.length; k += 1) {
      final kept = removalOrder.skip(k).map((b) => b.position).toList()..sort();
      alts.add(_splitAt(word, kept));
    }
    return alts; // 最后一个就是整词
  }

  /// 按给定断点位置把单词切开（位置必须升序）。
  List<String> _splitAt(String word, List<int> positions) {
    if (positions.isEmpty) return <String>[word];
    final parts = <String>[];
    var previous = 0;
    for (final position in positions) {
      parts.add(word.substring(previous, position));
      previous = position;
    }
    parts.add(word.substring(previous));
    return parts;
  }
}
