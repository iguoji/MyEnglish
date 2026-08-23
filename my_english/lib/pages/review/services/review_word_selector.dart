// Word 是复习选词器唯一处理的业务模型。
import '../../../models/word.dart';

///
/// 复习模块的固定选词器。
///
/// 本服务不读取首页当前的搜索、分组或排序按钮，只按照经过确认的复习优先级
/// 对完整词库排序。四个复习模块因此能在同一天复用完全相同的单词与顺序。
///
/// **排序规则（依次比较，前一项分出胜负就不再看后面）**：
/// 1. 复习时间升序——先没复习过的，再上次复习得早的，最后刚复习过的；
/// 2. 含义数量升序——释义条数少的先来，因为它更好记；
/// 3. 含义字数升序——条数一样时，释义正文更短的先来；
/// 4. 难度降序——难的排前面，多练几遍；
/// 5. 单词升序——按字母 A→Z；
/// 6. 编号升序——最后的稳定兜底，保证同样的词库永远排出同样的顺序。
///
/// 需要注意第 1 条的实际效果：`reviewedAt` 精确到毫秒，两个词几乎不可能撞上
/// 同一毫秒，所以只要一个词复习过，第 1 条基本就能分出胜负。也就是说
/// 第 2～4 条主要在「还没复习过的那批词之间」起作用。这是按确认的规则实现的，
/// 想让难度真正参与日常排序，需要把第 1 条改成按「复习日期」比较。
///
abstract final class ReviewWordSelector {
  ///
  /// 从完整词库中选出指定数量的复习单词。
  ///
  /// @param  `List<Word>`  words 完整且未软删除的本地词库。
  /// @param  int  limit 需要选出的数量。
  /// @param  `Set<int>`  exclude 需要跳过的单词主键，用于补词时排除已有的。
  /// @return `List<Word>` 固定顺序、不可修改的复习单词。
  ///
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
  /// 比较两个单词的复习优先级。
  ///
  /// @param  Word  first 左侧单词。
  /// @param  Word  second 右侧单词。
  /// @return int 负数表示 first 应排在前面。
  ///
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
  ///
  /// @param  DateTime?  first 左侧日期。
  /// @param  DateTime?  second 右侧日期。
  /// @return int 标准排序比较结果。
  ///
  static int _compareNullableDate(DateTime? first, DateTime? second) {
    if (first == null && second == null) return 0;
    if (first == null) return -1;
    if (second == null) return 1;
    return first.compareTo(second);
  }
}
