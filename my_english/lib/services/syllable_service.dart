// ============================================================================
//  业务服务层：在"纯算法"之上叠加 App 需要的逻辑
// ============================================================================
//  核心算法（liang_algorithm.dart）只负责"算"，本层负责"用"：
//    · getDivision      —— 优先用表里存的（含用户手动），否则当场算最细切法并落库；
//    · nextAlternative  —— 换一种合规切法（确定、有限、不随机），写回表；
//    · setUserDivision  —— 用户手动划分，最高优先级，必须落盘。
//
//  这一层可以包含"业务规则"（刷新顺序、手动优先），但核心算法保持纯净。
//  两者通过 SyllableStore 接口解耦：测试用内存、App 用手机数据库。
// ============================================================================

import '../store/syllable.dart';
import 'liang_algorithm.dart';

/// 音节切分服务（对外主入口）。
///
/// 用法：
///   final svc = SyllableService(InMemorySyllableStore());
///   final parts = await svc.getDivision('tradition'); // ["tradi", "tion"]
class SyllableService {
  final SyllableStore _store;
  // 纯算法核心；允许从外部传入，方便测试时注入同一个实例。
  final LiangHyphenator _hyphenator;

  SyllableService(this._store, [LiangHyphenator? hyphenator])
      : _hyphenator = hyphenator ?? LiangHyphenator();

  /// 取出一个单词的"默认音节划分"。
  ///
  /// 优先级（从高到低）：
  ///   1) 表里已存的划分（可能是用户手动 source=user，最高优先）；
  ///   2) 当场用算法算"最细切法"，并落库（source=algo）。
  Future<List<String>> getDivision(String word) async {
    final display = word.trim(); // 保留原始大小写，用于最终切分展示
    final w = display.toLowerCase(); // 小写只用于查规则表与做存储主键
    if (w.isEmpty) return [word];
    final row = await _store.getDivision(w);
    if (row != null) return row.parts;
    final parts = _hyphenator.split(display); // 最细切法（保留原始大小写）
    await _store.saveDivision(w, parts, 'algo');
    return parts;
  }

  /// 刷新：换一种"合规但不随机"的切法，并写回存储。
  ///
  /// 规则（确定且有限）：算法先给出全部合法断点；从最细切法开始，
  /// 每次合并"最弱的一个断点"变粗，直到整词；到头后再回到最细，循环。
  /// 注意：若存在用户手动划分，则刷新不覆盖它（手动最高优先级）。
  Future<List<String>> nextAlternative(String word) async {
    final display = word.trim();
    final w = display.toLowerCase();
    if (w.isEmpty) return [word];
    final row = await _store.getDivision(w);
    if (row != null && row.source == 'user') return row.parts; // 手动不参与刷新
    final alts = _alternatives(display);
    // 找到当前存的是第几个备选；找不到就当成最细(0)，跳到下一个。
    int idx = -1;
    if (row != null) {
      final joined = row.parts.join('|'); // 用普通字符做整体比较
      for (int i = 0; i < alts.length; i++) {
        if (alts[i].join('|') == joined) {
          idx = i;
          break;
        }
      }
    }
    final next = (idx + 1) % alts.length; // 循环：整词之后回到最细
    final parts = alts[next];
    await _store.saveDivision(w, parts, 'refresh');
    return parts;
  }

  /// 用户手动划分：最高优先级，必须落盘。
  Future<void> setUserDivision(String word, List<String> parts) async {
    final w = word.toLowerCase().trim();
    await _store.saveDivision(w, parts, 'user');
  }

  // ----- 以下为内部实现 -----

  /// 生成该词的"全部备选切法"，从最细到最粗（最后一个是整词）。
  ///
  /// 例如 tradition 的断点只有 1 个，则备选只有 [最细, 整词] 两种。
  /// banana 有 2 个断点，则有 [最细, 去掉弱断点, 整词] 三种。
  List<List<String>> _alternatives(String word) {
    // 规则表查的是小写词，但切分展示用原始大小写（长度一致，下标可直接套用）。
    final breaks = _hyphenator.breakPositions(word);
    // 移除顺序：先并最弱的（strength 小），同级按位置升序，确定不随机。
    final removalOrder = List<HyphenBreak>.from(breaks)
      ..sort((a, b) => a.strength != b.strength
          ? a.strength.compareTo(b.strength)
          : a.position.compareTo(b.position));
    final List<List<String>> alts = [];
    // alt[0] = 全部断点（最细）
    final allPos = breaks.map((b) => b.position).toList()..sort();
    alts.add(_splitAt(word, allPos));
    // 逐步去掉最弱断点，得到越来越粗的切法
    for (int k = 1; k <= removalOrder.length; k++) {
      final kept = removalOrder.skip(k).map((b) => b.position).toList()..sort();
      alts.add(_splitAt(word, kept));
    }
    return alts; // 最后一个就是整词
  }

  /// 按给定断点位置把单词切开（位置必须升序）。
  List<String> _splitAt(String word, List<int> positions) {
    if (positions.isEmpty) return [word];
    final parts = <String>[];
    int prev = 0;
    for (final p in positions) {
      parts.add(word.substring(prev, p));
      prev = p;
    }
    parts.add(word.substring(prev));
    return parts;
  }
}
