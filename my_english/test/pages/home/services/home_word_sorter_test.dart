// flutter_test 提供 test、expect 与集合匹配器。
import 'package:flutter_test/flutter_test.dart';
// Word 是排序服务接收的业务模型。
import 'package:my_english/models/word.dart';
// Meaning 提供词性与释义，用来构造含义数量或字符总数不同的单词。
import 'package:my_english/models/meaning.dart';
// 引入待测试的纯首页排序服务。
import 'package:my_english/pages/home/services/home_word_sorter.dart';
// WordSortField 定义主排序字段。
import 'package:my_english/pages/home/widgets/word_sort_bar.dart';

///
/// 验证从首页 State 抽离后的过滤、日期选择和稳定排序规则。
void main() {
  // 相同业务字段的记录必须保持输入顺序，避免页面刷新后行位置随机跳动。
  test('keeps original order when every business field is equal', () {
    // 两个对象故意使用相同字段且不提供 id。
    final first = Word(spelling: 'same', difficulty: 2);
    final second = Word(spelling: 'same', difficulty: 2);
    // 默认规则最终会落到原始下标兜底。
    const sorter = HomeWordSorter(
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
      Word(id: 2, spelling: 'Bravo'),
      Word(id: 1, spelling: 'alpha'),
    ];
    // 查询词使用大写转小写后的页面口径。
    const sorter = HomeWordSorter(
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

  // 2.0 起日期一律读复习时间，「更新时间 / 加入时间」视角已经下线。
  test('dateOf always reads the reviewed time', () {
    // 三种时间故意不同，确认只有复习时间被读取。
    final word = Word(
      spelling: 'dated',
      reviewedAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 2, 2),
      createdAt: DateTime(2026, 3, 3),
    );

    const sorter = HomeWordSorter(
      field: WordSortField.date,
      directions: <WordSortField, bool>{WordSortField.date: false},
      query: '',
    );

    // 日期固定只看复习时间（4.4 起词库仅剩按难度分组，无分组视角参数可传）。
    expect(sorter.dateOf(word), DateTime(2026, 1, 1));
  });

  // 含义入口先按释义数量升序：数量少的单词排在前。
  test('sorts by meaning count ascending', () {
    // 单释义单词，含义数 = 1。
    final few = Word(
      id: 1,
      spelling: 'apple',
      meanings: const <Meaning>[Meaning(pos: 'n.', definition: '苹果')],
    );
    // 两个词性共三条释义，含义数 = 3。
    final many = Word(
      id: 2,
      spelling: 'set',
      meanings: const <Meaning>[
        Meaning(pos: 'n.', definition: '集合'),
        Meaning(pos: 'n.', definition: '一套'),
        Meaning(pos: 'v.', definition: '放置'),
      ],
    );

    const sorter = HomeWordSorter(
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
    final shortMeaning = Word(
      id: 1,
      spelling: 'brief',
      meanings: const <Meaning>[Meaning(pos: 'n.', definition: '力')],
    );
    final longMeaning = Word(
      id: 2,
      spelling: 'verbose',
      meanings: const <Meaning>[Meaning(pos: 'n.', definition: '完成某件事情的能力')],
    );
    const sorter = HomeWordSorter(
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
    final lowFew = Word(
      id: 1,
      spelling: 'alpha',
      difficulty: 5,
      meanings: const <Meaning>[Meaning(pos: 'n.', definition: '甲')],
    );
    final lowMany = Word(
      id: 2,
      spelling: 'bravo',
      difficulty: 5,
      meanings: const <Meaning>[
        Meaning(pos: 'n.', definition: '乙'),
        Meaning(pos: 'n.', definition: '丙'),
      ],
    );

    const sorter = HomeWordSorter(
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
