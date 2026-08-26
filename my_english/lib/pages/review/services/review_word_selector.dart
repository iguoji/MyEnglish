// Word 是复习选词器唯一处理的业务模型。
import '../../../models/word.dart';

///
/// 复习模块的固定选词器。
///
/// 本服务不读取首页当前的搜索、分组或排序按钮，只按照经过确认的复习优先级
/// 对完整词库排序。四个复习模块因此能在同一天复用完全相同的单词与顺序。
///
/// **两层选词**（[selectTwoLayer]）：
/// 每天的复习词库分两批组装——
/// - **第一层（主批）**：占目标数量的 40%（向上取整）。规则把「难度」放在最前面，
///   先抓最难的那批词，让它们优先被练到。
/// - **第二层（副批）**：占剩下的 60%。规则沿用旧版「复习时间优先」的排序，
///   照顾没复习过或复习得早的词。
/// 两批合并就是今天的词库；第二层会排除第一层已经选中的主键，绝不重复。
///
/// **单层选词**（[select]）：只跑第二层规则，给「补词」「巩固局选明天词」等
/// 不需要难度分流的场景使用，行为与旧版完全一致。
///
abstract final class ReviewWordSelector {
  ///
  /// 第一层占目标数量的比例；0.4 即 40%。
  ///
  /// 想调整两层比例时改这一个常量即可，目前不开放为用户设置。
  static const double primaryRatio = 0.4;

  ///
  /// 按**两层规则**选出今天的复习单词。
  ///
  /// 执行步骤：
  /// 1. 过滤掉 `exclude` 与无主键的临时数据，复制成可排序副本；
  /// 2. 副本按 [comparePrimary]（第一层规则）排序，取前 `primaryCount` 个；
  /// 3. 剩余候选再按 [compare]（第二层规则）排序，取前 `secondaryCount` 个；
  /// 4. 两批按「第一层在前、第二层在后」拼接返回。
  ///
  /// `limit` 是今天的目标总数；`primaryCount = ceil(limit × 0.4)`，
  /// `secondaryCount = limit - primaryCount`。词库不足时各自取全部，
  /// 总数可能少于 `limit`。
  static List<Word> selectTwoLayer(
    List<Word> words, {
    required int limit,
    Set<int> exclude = const <int>{},
  }) {
    // 目标非正数或没有候选，直接返回共享空列表。
    if (limit <= 0 || words.isEmpty) return const <Word>[];
    // 过滤 + 复制，避免打乱调用方持有的原始顺序。
    final candidates = <Word>[
      for (final word in words)
        if (word.id == null || !exclude.contains(word.id)) word,
    ];
    if (candidates.isEmpty) return const <Word>[];

    // 第一层配额：向上取整，保证 limit=5 时第一层拿 2 个而不是 1 个。
    final primaryCount = (limit * primaryRatio).ceil();
    // 第二层配额：总数减去第一层。当第一层因向上取整超出 limit 时夹到 0。
    final secondaryCount = limit - primaryCount;

    // 第一层：难度优先，取走最难的那批。
    final primarySorted = List<Word>.of(candidates)
      ..sort(comparePrimary);
    final primaryPicked = primarySorted.take(primaryCount).toList();

    // 第二层候选：排除第一层已选主键，避免同一个词出现两次。
    final primaryIds = <int>{
      for (final word in primaryPicked)
        if (word.id != null) word.id!,
    };
    final secondaryCandidates = <Word>[
      for (final word in candidates)
        if (word.id == null || !primaryIds.contains(word.id)) word,
    ];

    // 第二层：复习时间优先。
    final secondarySorted = secondaryCandidates..sort(compare);
    // 第二层实际可取数 = min(配额, 剩余候选数)，防止越界。
    final secondaryTake = secondaryCount < secondarySorted.length
        ? secondaryCount
        : secondarySorted.length;
    final secondaryPicked = secondarySorted.take(secondaryTake).toList();

    // 两批合并；不可变包装，避免外部误改。
    return List<Word>.unmodifiable(<Word>[...primaryPicked, ...secondaryPicked]);
  }

  ///
  /// 按**单层规则**（第二层，即旧版六层规则）选出复习单词。
  ///
  /// 给补词、巩固局等不需要难度分流的场景用。行为与旧版完全一致。
  static List<Word> select(
    List<Word> words, {
    required int limit,
    Set<int> exclude = const <int>{},
  }) {
    // 非正目标没有可选单词，直接返回共享空列表。
    if (limit <= 0 || words.isEmpty) return const <Word>[];
    // 先过滤掉需要排除的主键，再复制成可排序的新列表。
    // 复制这一步很重要：直接排序会打乱首页 Store 持有的原始顺序。
    final candidates = <Word>[
      for (final word in words)
        if (word.id == null || !exclude.contains(word.id)) word,
    ];
    if (candidates.isEmpty) return const <Word>[];
    // 固定比较器不受任何界面状态影响。
    candidates.sort(compare);
    // 候选不足目标时取全部；否则只截取最优先的 limit 个。
    final count = limit < candidates.length ? limit : candidates.length;
    return List<Word>.unmodifiable(candidates.take(count));
  }

  ///
  /// **第一层**比较两个单词的优先级：难度降序打头，难的词先被挑出来。
  ///
  /// 规则（依次比较，前一项分出胜负就不再看后面）：
  /// 1. **难度降序**——越难越靠前；null 与首页约定一致按 0 处理；
  /// 2. **复习时间升序**——难度相同时，没复习过的先来，再按复习时间从早到晚；
  /// 3. 含义数量升序；
  /// 4. 含义字数升序；
  /// 5. 单词升序（忽略大小写）；
  /// 6. 编号升序。
  static int comparePrimary(Word first, Word second) {
    // 第一层：难度降序。越难的越靠前；null 与首页约定一致按 0 处理。
    final byDifficulty = (second.difficulty ?? 0).compareTo(
      first.difficulty ?? 0,
    );
    if (byDifficulty != 0) return byDifficulty;

    // 第二层：复习时间升序，没复习过的（null）永远排在最前面。
    final byReviewed = _compareNullableDate(first.reviewedAt, second.reviewedAt);
    if (byReviewed != 0) return byReviewed;

    // 第三、四层：含义复杂度升序（释义条数 → 释义字符数）。
    final byMeaning = first.compareMeaningComplexityTo(second);
    if (byMeaning != 0) return byMeaning;

    // 第五层：英文拼写忽略大小写后按 A 到 Z 排列。
    final bySpelling = first.spelling.toLowerCase().compareTo(
      second.spelling.toLowerCase(),
    );
    if (bySpelling != 0) return bySpelling;

    // 第六层：数据库编号是最后的稳定兜底；无编号的临时数据放在已落库数据后面。
    if (first.id == null && second.id == null) return 0;
    if (first.id == null) return 1;
    if (second.id == null) return -1;
    return first.id!.compareTo(second.id!);
  }

  ///
  /// **第二层**比较两个单词的复习优先级（即旧版六层规则）。
  ///
  /// 规则（依次比较，前一项分出胜负就不再看后面）：
  /// 1. 复习时间升序——先没复习过的，再上次复习得早的，最后刚复习过的；
  /// 2. 含义数量升序——释义条数少的先来，因为它更好记；
  /// 3. 含义字数升序——条数一样时，释义正文更短的先来；
  /// 4. 难度降序——难的排前面，多练几遍；
  /// 5. 单词升序——按字母 A→Z；
  /// 6. 编号升序——最后的稳定兜底，保证同样的词库永远排出同样的顺序。
  static int compare(Word first, Word second) {
    // 第一层：复习时间升序，没复习过的（null）永远排在最前面。
    // 这一层等价于 MySQL 的 `ORDER BY reviewed_at ASC`，NULL 视为最小。
    final byReviewed = _compareNullableDate(first.reviewedAt, second.reviewedAt);
    if (byReviewed != 0) return byReviewed;

    // 第二、三层：含义复杂度升序。统一比较器固定执行
    // 「释义条数 → 释义字符数」，两层都采用升序，简单的词先背。
    final byMeaning = first.compareMeaningComplexityTo(second);
    if (byMeaning != 0) return byMeaning;

    // 第四层：难度降序。越难的越靠前；null 与首页约定一致按 0 处理。
    final byDifficulty = (second.difficulty ?? 0).compareTo(
      first.difficulty ?? 0,
    );
    if (byDifficulty != 0) return byDifficulty;

    // 第五层：英文拼写忽略大小写后按 A 到 Z 排列。
    final bySpelling = first.spelling.toLowerCase().compareTo(
      second.spelling.toLowerCase(),
    );
    if (bySpelling != 0) return bySpelling;

    // 第六层：数据库编号是最后的稳定兜底；无编号的临时数据放在已落库数据后面。
    if (first.id == null && second.id == null) return 0;
    if (first.id == null) return 1;
    if (second.id == null) return -1;
    return first.id!.compareTo(second.id!);
  }

  ///
  /// 升序比较可空日期；没有日期的排在有日期的前面。
  ///
  /// 生活化解释：`null` 代表「这个词还没复习过」，它当然要最优先安排。
  static int _compareNullableDate(DateTime? first, DateTime? second) {
    if (first == null && second == null) return 0;
    if (first == null) return -1;
    if (second == null) return 1;
    return first.compareTo(second);
  }
}
