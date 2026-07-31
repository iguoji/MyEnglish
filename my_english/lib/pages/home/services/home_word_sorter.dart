// Word 是排序服务处理的业务模型。
import '../../../models/word.dart';
// GroupMode 决定“日期”字段具体使用复习、更新还是加入时间。
import '../widgets/group_filter_bar.dart';
// WordSortField 定义首页可选的四种排序入口。
import '../widgets/word_sort_bar.dart';

///
/// 首页单词过滤与稳定排序服务。
///
/// 它只接收数据和排序参数，不持有 Widget 或页面状态，作用类似 PHP 中独立的
/// Collection/Service：页面负责交互，本类负责可重复测试的业务比较规则。
///
class HomeWordSorter {
  ///
  /// 保存本次过滤与排序需要的全部只读参数。
  ///
  /// @param  GroupMode  mode
  /// @param  WordSortField  field
  /// @param  `Map<WordSortField, bool>`  directions
  /// @param  String  query
  ///
  const HomeWordSorter({
    required this.mode,
    required this.field,
    required this.directions,
    required this.query,
  });

  ///
  /// 当前分组视角，用来决定日期字段的来源。
  ///
  /// @var GroupMode
  ///
  final GroupMode mode;

  ///
  /// 当前选中的排序字段。
  ///
  /// @var WordSortField
  ///
  final WordSortField field;

  ///
  /// 每个字段各自记住的升降序；true 为升序，false 为降序。
  ///
  /// @var `Map<WordSortField, bool>`
  ///
  final Map<WordSortField, bool> directions;

  ///
  /// 已转成小写的搜索词；空字符串表示不过滤。
  ///
  /// @var String
  ///
  final String query;

  ///
  /// 按当前分组模式返回列表行显示和日期排序共同使用的时间。
  ///
  /// @param  Word  word
  /// @return DateTime?
  ///
  DateTime? dateOf(Word word) => switch (mode) {
    // 更新时间视角读取 updatedAt。
    GroupMode.updated => word.updatedAt,
    // 加入时间视角读取 createdAt。
    GroupMode.added => word.createdAt,
    // 自定义、难度和复习视角统一读取 reviewedAt。
    _ => word.reviewedAt,
  };

  ///
  /// 先按拼写过滤，再使用稳定的多级规则排序并返回新列表。
  ///
  /// @param  `List<Word>`  source
  /// @return `List<Word>`
  ///
  List<Word> filterAndSort(List<Word> source) {
    // 不直接修改 Store 的源列表，避免一个分组排序影响另一个分组。
    final filtered = query.isEmpty
        ? List<Word>.of(source)
        : source
              .where((word) => word.spelling.toLowerCase().contains(query))
              .toList();
    // Dart 的 List.sort 不保证稳定；记录原始下标作为所有业务字段相等时的最后兜底。
    final originalIndexes = <Word, int>{};
    for (var index = 0; index < filtered.length; index += 1) {
      // Word 当前按对象身份作为键，同拼写的不同记录不会互相覆盖。
      originalIndexes[filtered[index]] = index;
    }
    // 找不到方向时采用升序，保证新增字段也有确定行为。
    final isAscending = directions[field] ?? true;
    // 比较器先跑业务规则，完全相等时恢复输入顺序。
    filtered.sort((first, second) {
      // 多级业务比较返回负数、0 或正数，与 PHP usort 的比较器约定相同。
      final result = _compareWords(first, second, isAscending);
      // 已经分出先后时直接返回。
      if (result != 0) return result;
      // 业务字段完全相同，按原始下标保持稳定。
      return (originalIndexes[first] ?? 0).compareTo(
        originalIndexes[second] ?? 0,
      );
    });
    // 返回过滤和排序后的副本。
    return filtered;
  }

  ///
  /// 按选中字段执行固定的多级比较链。
  ///
  /// @param  Word  first
  /// @param  Word  second
  /// @param  bool  isAscending
  /// @return int
  ///
  int _compareWords(Word first, Word second, bool isAscending) {
    // 每个入口都明确列出第二、第三层规则，避免相同主字段时顺序随机跳动。
    switch (field) {
      case WordSortField.original:
        // 默认：编号升序 -> 字母升序 -> 难度降序 -> 日期降序。
        final byId = _compareId(first, second);
        if (byId != 0) return byId;
        final bySpelling = _compareSpelling(first, second, true);
        if (bySpelling != 0) return bySpelling;
        final byDifficulty = _compareDifficulty(first, second, false);
        if (byDifficulty != 0) return byDifficulty;
        return _compareDate(first, second, false);
      case WordSortField.alphabet:
        // 字母：当前方向 -> 难度降序 -> 日期降序 -> 编号升序。
        final bySpelling = _compareSpelling(first, second, isAscending);
        if (bySpelling != 0) return bySpelling;
        final byDifficulty = _compareDifficulty(first, second, false);
        if (byDifficulty != 0) return byDifficulty;
        final byDate = _compareDate(first, second, false);
        if (byDate != 0) return byDate;
        return _compareId(first, second);
      case WordSortField.difficulty:
        // 难度：当前方向 -> 日期降序 -> 字母升序 -> 编号升序。
        final byDifficulty = _compareDifficulty(first, second, isAscending);
        if (byDifficulty != 0) return byDifficulty;
        final byDate = _compareDate(first, second, false);
        if (byDate != 0) return byDate;
        final bySpelling = _compareSpelling(first, second, true);
        if (bySpelling != 0) return bySpelling;
        return _compareId(first, second);
      case WordSortField.date:
        // 日期：当前方向 -> 难度降序 -> 字母升序 -> 编号升序。
        final byDate = _compareDate(first, second, isAscending);
        if (byDate != 0) return byDate;
        final byDifficulty = _compareDifficulty(first, second, false);
        if (byDifficulty != 0) return byDifficulty;
        final bySpelling = _compareSpelling(first, second, true);
        if (bySpelling != 0) return bySpelling;
        return _compareId(first, second);
    }
  }

  ///
  /// 忽略大小写比较拼写，再按指定方向返回结果。
  ///
  /// @param  Word  first
  /// @param  Word  second
  /// @param  bool  isAscending
  /// @return int
  ///
  int _compareSpelling(Word first, Word second, bool isAscending) {
    // 搜索同样使用小写，因此过滤和排序对大小写的理解保持一致。
    final comparison = first.spelling.toLowerCase().compareTo(
      second.spelling.toLowerCase(),
    );
    // 降序通过翻转比较结果实现。
    return _applyDirection(comparison, isAscending);
  }

  ///
  /// 比较难度；null 按业务约定视为 0。
  ///
  /// @param  Word  first
  /// @param  Word  second
  /// @param  bool  isAscending
  /// @return int
  ///
  int _compareDifficulty(Word first, Word second, bool isAscending) {
    // ?? 类似 PHP 的 null 合并运算符。
    final comparison = (first.difficulty ?? 0).compareTo(
      second.difficulty ?? 0,
    );
    // 应用当前方向。
    return _applyDirection(comparison, isAscending);
  }

  ///
  /// 比较当前视角对应的日期。
  ///
  /// @param  Word  first
  /// @param  Word  second
  /// @param  bool  isAscending
  /// @return int
  ///
  int _compareDate(Word first, Word second, bool isAscending) {
    // 升序时空日期排在最前，降序时排在最后，与难度 null=0 的方向语义一致。
    return _compareNullable<DateTime>(
      dateOf(first),
      dateOf(second),
      (firstValue, secondValue) => firstValue.compareTo(secondValue),
      isAscending,
      nullsLast: !isAscending,
    );
  }

  ///
  /// 编号始终升序，没有编号的测试或临时数据排在已有编号之后。
  ///
  /// @param  Word  first
  /// @param  Word  second
  /// @return int
  ///
  int _compareId(Word first, Word second) {
    // 两个编号都为空时返回 0，最后由输入下标保持稳定。
    return _compareNullable<int>(
      first.id,
      second.id,
      (firstValue, secondValue) => firstValue.compareTo(secondValue),
      true,
    );
  }

  ///
  /// 比较两个可空值，并明确控制空值位于开头还是末尾。
  ///
  /// @param  T?  first
  /// @param  T?  second
  /// @param  `int Function(T first, T second)`  compareValues
  /// @param  bool  isAscending
  /// @param  bool  nullsLast
  /// @return int
  ///
  int _compareNullable<T>(
    T? first,
    T? second,
    int Function(T first, T second) compareValues,
    bool isAscending, {
    bool nullsLast = true,
  }) {
    // 两边都为空时业务字段相同。
    if (first == null && second == null) return 0;
    // 只有左边为空时，按 nullsLast 决定它在前还是在后。
    if (first == null) return nullsLast ? 1 : -1;
    // 只有右边为空时使用相反结果。
    if (second == null) return nullsLast ? -1 : 1;
    // 两边都有值后才应用升降序。
    return _applyDirection(compareValues(first, second), isAscending);
  }

  ///
  /// 给普通升序比较结果应用用户选择的方向。
  ///
  /// @param  int  comparison
  /// @param  bool  isAscending
  /// @return int
  ///
  int _applyDirection(int comparison, bool isAscending) {
    // 升序保持符号，降序翻转符号。
    return isAscending ? comparison : -comparison;
  }
}
