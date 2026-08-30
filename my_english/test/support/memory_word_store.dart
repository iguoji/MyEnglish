// 单词模型与单词 Store 接口。
import 'package:my_english/models/word.dart';
import 'package:my_english/store/word.dart';

///
/// 单词 Store 的内存测试实现。
///
/// 持有一份可变的词表，并复刻原生 SQLite 的 `pickWords` 两层排序：
/// - hard：难度降序 → 复习时间升序 → 含义复杂度升序 → 拼写升序 → 编号升序；
/// - stale：复习时间升序 → 难度降序 → 含义复杂度升序 → 拼写升序 → 编号升序。
///
/// 其余读写方法按调用原样记账或返回安全默认值。
///
class MemoryWordStore implements WordStore {
  ///
  /// 创建内存词表；[words] 会被复制，测试中可以安全修改原列表。
  MemoryWordStore(List<Word> words) : words = List<Word>.of(words);

  ///
  /// 当前词表；测试可以增删改来模拟真实词库变化。
  final List<Word> words;

  ///
  /// 按调用顺序记下的全部 pickWords 请求。
  final List<({int limit, List<int> exclude, PickLayer layer})> picks =
      <({int limit, List<int> exclude, PickLayer layer})>[];

  ///
  /// 返回的单词主键列表；顺序与原生 SQL 排序一致。
  @override
  Future<List<int>> pickWords({
    required int limit,
    List<int> exclude = const <int>[],
    PickLayer layer = PickLayer.stale,
  }) async {
    picks.add((limit: limit, exclude: List<int>.of(exclude), layer: layer));
    final pool = <Word>[
      for (final word in words)
        if (word.id != null && !exclude.contains(word.id)) word,
    ];
    // hard 层先按难度降序（难词优先），stale 层先按复习时间升序（久未复习优先）。
    pool.sort(
      (first, second) => layer == PickLayer.hard
          ? _compareHard(first, second)
          : _compareStale(first, second),
    );
    return List<int>.unmodifiable(
      <int>[for (final word in pool.take(limit)) word.id!],
    );
  }

  ///
  /// 难度降序 → 复习时间升序 → 含义复杂度升序 → 拼写升序 → 编号升序。
  int _compareHard(Word first, Word second) {
    var result = second.difficulty.compareTo(first.difficulty);
    if (result != 0) return result;
    result = _compareReviewAsc(first, second);
    if (result != 0) return result;
    result = first.compareMeaningComplexityTo(second);
    if (result != 0) return result;
    result = first.spelling.toLowerCase().compareTo(second.spelling.toLowerCase());
    if (result != 0) return result;
    return (first.id ?? 0).compareTo(second.id ?? 0);
  }

  ///
  /// 复习时间升序 → 难度降序 → 含义复杂度升序 → 拼写升序 → 编号升序。
  int _compareStale(Word first, Word second) {
    var result = _compareReviewAsc(first, second);
    if (result != 0) return result;
    result = second.difficulty.compareTo(first.difficulty);
    if (result != 0) return result;
    result = first.compareMeaningComplexityTo(second);
    if (result != 0) return result;
    result = first.spelling.toLowerCase().compareTo(second.spelling.toLowerCase());
    if (result != 0) return result;
    return (first.id ?? 0).compareTo(second.id ?? 0);
  }

  ///
  /// 复习时间升序；null（从未复习）排在最前。
  int _compareReviewAsc(Word first, Word second) {
    final a = first.reviewedAt;
    final b = second.reviewedAt;
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    return a.compareTo(b);
  }

  @override
  Future<List<Word>> getAll() async => List<Word>.unmodifiable(words);

  @override
  Future<List<Word>> getByIds(List<int> ids) async => List<Word>.unmodifiable(
    <Word>[
      for (final word in words)
        if (word.id != null && ids.contains(word.id)) word,
    ],
  );

  @override
  Future<List<Word>> getByMeaningIds(List<int> meaningIds) async =>
      const <Word>[];

  @override
  Future<int> create(Word word) async => 1;

  @override
  Future<void> update(Word word) async {}

  @override
  Future<void> delete(int id) async {
    words.removeWhere((word) => word.id == id);
  }

  @override
  Future<void> saveWordConfusions(int wordId, List<String> confusions) async {}

  @override
  Future<void> saveMeaningConfusions(int meaningId, List<String> confusions) async {}

  @override
  Future<void> saveWordSyllables(int wordId, List<String> syllables) async {}

  @override
  Future<void> importData(Map<String, Object?> data) async {}

  @override
  Future<Map<String, Object?>> exportData() async => <String, Object?>{};

  @override
  Future<void> clearAll() async {
    words.clear();
  }
}
