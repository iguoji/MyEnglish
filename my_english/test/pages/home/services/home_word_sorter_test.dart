// flutter_test 提供 test、expect 与集合匹配器。
import 'package:flutter_test/flutter_test.dart';
// Word 是排序服务接收的业务模型。
import 'package:my_english/models/word.dart';
// 引入待测试的纯首页排序服务。
import 'package:my_english/pages/home/services/home_word_sorter.dart';
// GroupMode 决定日期排序使用哪个时间字段。
import 'package:my_english/pages/home/widgets/group_filter_bar.dart';
// WordSortField 定义主排序字段。
import 'package:my_english/pages/home/widgets/word_sort_bar.dart';

/// 验证从首页 State 抽离后的过滤、日期选择和稳定排序规则。
void main() {
  // 相同业务字段的记录必须保持输入顺序，避免页面刷新后行位置随机跳动。
  test('keeps original order when every business field is equal', () {
    // 两个对象故意使用相同字段且不提供 id。
    const first = Word(spelling: 'same', difficulty: 2);
    const second = Word(spelling: 'same', difficulty: 2);
    // 默认规则最终会落到原始下标兜底。
    const sorter = HomeWordSorter(
      mode: GroupMode.custom,
      field: WordSortField.alphabet,
      directions: <WordSortField, bool>{WordSortField.alphabet: true},
      query: '',
    );

    // identical 同时证明返回顺序对应原对象，而不是只比较字符串结果。
    final sorted = sorter.filterAndSort(<Word>[first, second]);
    expect(identical(sorted[0], first), isTrue);
    expect(identical(sorted[1], second), isTrue);
  });

  // 搜索忽略大小写，并且排序只修改副本、不污染 Store 源列表。
  test('filters case-insensitively without mutating source', () {
    // 源顺序故意与字母升序相反。
    final source = <Word>[
      const Word(id: 2, spelling: 'Bravo'),
      const Word(id: 1, spelling: 'alpha'),
    ];
    // 查询词使用大写转小写后的页面口径。
    const sorter = HomeWordSorter(
      mode: GroupMode.custom,
      field: WordSortField.alphabet,
      directions: <WordSortField, bool>{WordSortField.alphabet: true},
      query: 'a',
    );

    // 两项都包含 a，输出按字母升序。
    expect(sorter.filterAndSort(source).map((word) => word.spelling), <String>[
      'alpha',
      'Bravo',
    ]);
    // 原列表仍保持 Store 提供的顺序。
    expect(source.map((word) => word.spelling), <String>['Bravo', 'alpha']);
  });

  // 日期字段必须跟随分组视角，不能继续使用旧版 effectiveDate 回退链。
  test('selects the date field from the active group mode', () {
    // 三种时间故意不同，方便精确确认每个模式的选择。
    final word = Word(
      spelling: 'dated',
      reviewedAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 2, 2),
      createdAt: DateTime(2026, 3, 3),
    );
    // 工厂函数只替换 mode，其余参数与 dateOf 无关。
    HomeWordSorter sorter(GroupMode mode) => HomeWordSorter(
      mode: mode,
      field: WordSortField.date,
      directions: const <WordSortField, bool>{WordSortField.date: false},
      query: '',
    );

    // 默认/复习视角读取 reviewedAt。
    expect(sorter(GroupMode.custom).dateOf(word), DateTime(2026, 1, 1));
    // 更新时间视角只读取 updatedAt。
    expect(sorter(GroupMode.updated).dateOf(word), DateTime(2026, 2, 2));
    // 加入时间视角只读取 createdAt。
    expect(sorter(GroupMode.added).dateOf(word), DateTime(2026, 3, 3));
  });
}
