// Word 是每日复习词单筛选器唯一处理的业务模型。
import '../../../models/word.dart';

///
/// 每日公共复习词单的固定选择器。
///
/// 本服务不读取首页当前搜索、分组或排序按钮，只按照经过确认的复习优先级
/// 对完整词库排序。四种复习模式因此能在同一天复用完全相同的单词与顺序。
///
abstract final class DailyReviewSelector {
  ///
  /// 从完整词库中选出指定数量的每日复习单词。
  ///
  /// 固定比较链：未复习优先 → 业务日期升序 → 释义条数升序 →
  /// 释义字符数升序 → 难度降序 → 字母升序 → 编号升序。
  ///
  /// @param  `List<Word>`  words 完整且未软删除的本地词库。
  /// @param  int  limit 当天首次生成词单时冻结的目标数量。
  /// @return `List<Word>` 固定顺序、不可修改的每日复习单词。
  ///
  static List<Word> select(List<Word> words, {required int limit}) {
    // 非正目标没有可选单词，直接返回共享空列表。
    if (limit <= 0 || words.isEmpty) return const <Word>[];
    // 复制源列表，避免排序改变首页 Store 持有的原始顺序。
    final sorted = List<Word>.of(words);
    // 固定比较器不受任何界面状态影响。
    sorted.sort(compare);
    // 词库不足目标时取全部；否则只截取最优先的 limit 个。
    final count = limit < sorted.length ? limit : sorted.length;
    return List<Word>.unmodifiable(sorted.take(count));
  }

  ///
  /// 比较两个单词的每日复习优先级。
  ///
  /// @param  Word  first 左侧单词。
  /// @param  Word  second 右侧单词。
  /// @return int 负数表示 first 应排在前面。
  ///
  static int compare(Word first, Word second) {
    // reviewedAt 为空表示从未复习；false 比 true 靠前，确保未复习永远优先。
    final firstReviewedRank = first.reviewedAt == null ? 0 : 1;
    final secondReviewedRank = second.reviewedAt == null ? 0 : 1;
    final byReviewed = firstReviewedRank.compareTo(secondReviewedRank);
    if (byReviewed != 0) return byReviewed;

    // 未复习词使用“更新 → 加入”的回退日期；已复习词使用最近复习日期。
    final firstDate = first.reviewedAt ?? first.updatedAt ?? first.createdAt;
    final secondDate =
        second.reviewedAt ?? second.updatedAt ?? second.createdAt;
    final byDate = _compareNullableDate(firstDate, secondDate);
    if (byDate != 0) return byDate;

    // 统一比较器固定执行“释义数量 → 释义字符数”，两层都采用升序。
    final byMeaning = first.compareMeaningComplexityTo(second);
    if (byMeaning != 0) return byMeaning;

    // 难度越高越靠前；null 与首页约定一致按 0 处理。
    final byDifficulty = (second.difficulty ?? 0).compareTo(
      first.difficulty ?? 0,
    );
    if (byDifficulty != 0) return byDifficulty;

    // 英文拼写忽略大小写后按 A 到 Z 排列。
    final bySpelling = first.spelling.toLowerCase().compareTo(
      second.spelling.toLowerCase(),
    );
    if (bySpelling != 0) return bySpelling;

    // 数据库编号是最后稳定兜底；无编号临时数据放在已落库数据后面。
    if (first.id == null && second.id == null) return 0;
    if (first.id == null) return 1;
    if (second.id == null) return -1;
    return first.id!.compareTo(second.id!);
  }

  ///
  /// 升序比较可空日期；没有任何日期的数据排在有日期的数据前面。
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
