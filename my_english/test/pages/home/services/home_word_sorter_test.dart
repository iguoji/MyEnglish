// flutter_test 提供 test、expect 与集合匹配器。
import 'package:flutter_test/flutter_test.dart';
// Word 是排序服务接收的业务模型。
import 'package:my_english/models/word.dart';
// Meaning 提供词性与释义，用来构造含义数量或字符总数不同的单词。
import 'package:my_english/models/meaning.dart';
// 引入待测试的纯首页排序服务。
import 'package:my_english/pages/home/services/home_word_sorter.dart';
// GroupMode 决定日期排序使用哪个时间字段。
import 'package:my_english/pages/home/widgets/group_filter_bar.dart';
// WordSortField 定义主排序字段。
import 'package:my_english/pages/home/widgets/word_sort_bar.dart';

///
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
      field: WordSortField.original,
      directions: <WordSortField, bool>{WordSortField.original: true},
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
      field: WordSortField.original,
      directions: <WordSortField, bool>{WordSortField.original: true},
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

    ///
    /// 创建指定分组视角的排序服务，其余参数保持固定。
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

  // 含义入口先按释义数量升序：数量少的单词排在前。
  test('sorts by meaning count ascending', () {
    // 单释义单词，含义数 = 1。
    const few = Word(
      id: 1,
      spelling: 'apple',
      meanings: <Meaning>[
        Meaning(index: 0, pos: 'n.', definitions: <String>['苹果']),
      ],
    );
    // 两词性共三条释义，含义数 = 3。
    const many = Word(
      id: 2,
      spelling: 'set',
      meanings: <Meaning>[
        Meaning(index: 1, pos: 'n.', definitions: <String>['集合', '一套']),
        Meaning(index: 0, pos: 'v.', definitions: <String>['放置']),
      ],
    );

    const sorter = HomeWordSorter(
      mode: GroupMode.custom,
      field: WordSortField.meaning,
      directions: <WordSortField, bool>{WordSortField.meaning: true},
      query: '',
    );

    // 含义少的 apple 必然排在 set 之前。
    expect(
      sorter.filterAndSort(<Word>[many, few]).map((word) => word.id),
      <int>[1, 2],
    );
  });

  // 释义条数相同时继续比较全部释义正文的字符总数，短释义排在前面。
  test('uses meaning character count after meaning count', () {
    // 两个单词都只有一条释义，单靠 meaningCount 无法区分先后。
    const shortMeaning = Word(
      id: 1,
      spelling: 'brief',
      meanings: <Meaning>[
        Meaning(index: 0, pos: 'n.', definitions: <String>['力']),
      ],
    );
    const longMeaning = Word(
      id: 2,
      spelling: 'verbose',
      meanings: <Meaning>[
        Meaning(index: 0, pos: 'n.', definitions: <String>['完成某件事情的能力']),
      ],
    );
    const sorter = HomeWordSorter(
      mode: GroupMode.custom,
      field: WordSortField.meaning,
      directions: <WordSortField, bool>{WordSortField.meaning: true},
      query: '',
    );

    // 即使输入顺序相反，单字符释义仍应排在长释义前面。
    expect(
      sorter
          .filterAndSort(<Word>[longMeaning, shortMeaning])
          .map((word) => word.id),
      <int>[1, 2],
    );
  });

  // 难度相等时，含义复杂度作为次级规则生效（先数量、再字符数）。
  test('uses meaning count as tiebreaker after difficulty', () {
    // 两者难度相同，但释义条数不同。
    const lowFew = Word(
      id: 1,
      spelling: 'alpha',
      difficulty: 5,
      meanings: <Meaning>[
        Meaning(index: 0, pos: 'n.', definitions: <String>['甲']),
      ],
    );
    const lowMany = Word(
      id: 2,
      spelling: 'bravo',
      difficulty: 5,
      meanings: <Meaning>[
        Meaning(index: 0, pos: 'n.', definitions: <String>['乙', '丙']),
      ],
    );

    const sorter = HomeWordSorter(
      mode: GroupMode.custom,
      field: WordSortField.difficulty,
      directions: <WordSortField, bool>{WordSortField.difficulty: false},
      query: '',
    );

    // 难度同为 5，按“含义升序”次级规则：单释义的 alpha 排在双释义的 bravo 之前。
    expect(
      sorter.filterAndSort(<Word>[lowMany, lowFew]).map((word) => word.id),
      <int>[1, 2],
    );
  });
}
