import 'package:flutter_test/flutter_test.dart';
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';
import 'package:my_english/pages/review/services/review_word_selector.dart';

///
/// 构造一个用于排序断言的单词。
Word _word(
  int id,
  String spelling, {
  List<String> definitions = const <String>['释义'],
  int difficulty = 0,
  DateTime? reviewedAt,
}) => Word(
  id: id,
  spelling: spelling,
  meanings: <Meaning>[
    Meaning(index: 0, pos: 'n.', definitions: definitions),
  ],
  difficulty: difficulty,
  reviewedAt: reviewedAt,
);

///
/// 取出选词结果的主键，让断言只关注顺序本身。
List<int> _ids(List<Word> words) => words.map((word) => word.id!).toList();

///
/// 验证复习选词规则的六层比较顺序与补词时的排除能力。
void main() {
  test('从未复习的单词永远排在复习过的前面', () {
    final words = <Word>[
      _word(1, 'alpha', reviewedAt: DateTime(2026, 8, 1)),
      _word(2, 'beta'),
      _word(3, 'gamma', reviewedAt: DateTime(2026, 1, 1)),
      _word(4, 'delta'),
    ];

    // 两个没复习过的先来（内部再按后续规则排），复习过的按时间从早到晚。
    expect(_ids(ReviewWordSelector.select(words, limit: 4)), <int>[2, 4, 3, 1]);
  });

  test('复习时间越早越优先，精确到毫秒', () {
    final base = DateTime(2026, 8, 20, 10);
    final words = <Word>[
      _word(1, 'alpha', reviewedAt: base.add(const Duration(milliseconds: 2))),
      _word(2, 'beta', reviewedAt: base),
      _word(3, 'gamma', reviewedAt: base.add(const Duration(milliseconds: 1))),
    ];

    expect(_ids(ReviewWordSelector.select(words, limit: 3)), <int>[2, 3, 1]);
  });

  test('都没复习过时依次比含义条数、含义字数、难度、拼写、编号', () {
    final words = <Word>[
      // 释义两条，条数最多，排最后。
      _word(10, 'aaa', definitions: <String>['甲', '乙']),
      // 一条释义但正文更长。
      _word(11, 'bbb', definitions: <String>['很长的一条释义']),
      // 一条短释义、难度 3。
      _word(12, 'ccc', definitions: <String>['短'], difficulty: 3),
      // 一条同样长度的释义、难度 1：难度低所以排在 ccc 后面。
      _word(13, 'ddd', definitions: <String>['短'], difficulty: 1),
    ];

    // 条数升序 → 字数升序 → 难度降序。
    expect(
      _ids(ReviewWordSelector.select(words, limit: 4)),
      <int>[12, 13, 11, 10],
    );
  });

  test('前面全部打平时按拼写忽略大小写升序，再按编号兜底', () {
    final words = <Word>[
      _word(30, 'Banana'),
      _word(20, 'apple'),
      // 与 20 拼写完全相同，只能靠编号分出先后。
      _word(21, 'apple'),
    ];

    expect(
      _ids(ReviewWordSelector.select(words, limit: 3)),
      <int>[20, 21, 30],
    );
  });

  test('exclude 让补词时不会重复选到词库里已有的单词', () {
    final words = <Word>[
      _word(1, 'alpha'),
      _word(2, 'beta'),
      _word(3, 'gamma'),
    ];

    // 不排除时前两个就是 1、2；排除掉它们之后只能拿到 3。
    expect(_ids(ReviewWordSelector.select(words, limit: 2)), <int>[1, 2]);
    expect(
      _ids(
        ReviewWordSelector.select(
          words,
          limit: 2,
          exclude: <int>{1, 2},
        ),
      ),
      <int>[3],
    );
  });

  test('目标非正数或词库为空时返回空列表', () {
    final words = <Word>[_word(1, 'alpha')];
    expect(ReviewWordSelector.select(words, limit: 0), isEmpty);
    expect(ReviewWordSelector.select(words, limit: -3), isEmpty);
    expect(ReviewWordSelector.select(const <Word>[], limit: 5), isEmpty);
  });

  test('词库不足目标时返回全部，不会报错', () {
    final words = <Word>[_word(1, 'alpha'), _word(2, 'beta')];
    expect(_ids(ReviewWordSelector.select(words, limit: 10)), <int>[1, 2]);
  });

  test('选词不会改变调用方持有的原始列表顺序', () {
    final words = <Word>[
      _word(3, 'gamma'),
      _word(1, 'alpha'),
      _word(2, 'beta'),
    ];
    ReviewWordSelector.select(words, limit: 3);
    // 排序发生在内部副本上，外部列表必须原封不动。
    expect(_ids(words), <int>[3, 1, 2]);
  });

  // ──────────────────────────────────────────────────────────────
  //  两层选词（selectTwoLayer）测试组
  // ──────────────────────────────────────────────────────────────

  test('两层选词：第一层优先抓难度最高的词', () {
    // 4 个词难度依次 1/2/3/4，其余字段完全一致（都没复习过、释义相同）。
    final words = <Word>[
      _word(1, 'a', difficulty: 1),
      _word(2, 'b', difficulty: 2),
      _word(3, 'c', difficulty: 3),
      _word(4, 'd', difficulty: 4),
    ];

    // limit=4 → 第一层 ceil(4×0.4)=2，按难度降序取 [4, 3]；
    // 第二层排除 {3,4} 后剩 [1,2]，按第二层规则（复习时间全空→含义全同→
    // 难度降序）排成 [2, 1]。
    // 合并结果：第一层 [4,3] + 第二层 [2,1] = [4,3,2,1]。
    expect(
      _ids(ReviewWordSelector.selectTwoLayer(words, limit: 4)),
      <int>[4, 3, 2, 1],
    );
  });

  test('两层选词：第二层按复习时间排，不被难度干扰', () {
    // 第一层把高难度词挑走后，第二层剩下的词复习时间各不相同。
    final words = <Word>[
      // 难度 5、复习在 8 月：会被第一层抓走。
      _word(1, 'a', difficulty: 5, reviewedAt: DateTime(2026, 8)),
      // 难度 1、复习在 1 月：第二层里复习最早，应排最前。
      _word(2, 'b', difficulty: 1, reviewedAt: DateTime(2026, 1)),
      // 难度 3、没复习过：第二层里 null 最优先。
      _word(3, 'c', difficulty: 3),
      // 难度 2、复习在 8 月：第二层里复习最晚，排最后。
      _word(4, 'd', difficulty: 2, reviewedAt: DateTime(2026, 8)),
    ];

    // 第一层 ceil(4×0.4)=2，按难度降序：a(5)、c(3) → [1, 3]。
    // 第二层排除 {1,3} 后剩 b(复习1月)、d(复习8月)，
    // 按第二层规则复习时间升序：b(1月) 在 d(8月) 前 → [2, 4]。
    // 注意 d 难度(2) 比 b 难度(1) 高，但第二层复习时间优先级高于难度，
    // 所以 b 仍排在 d 前面——这正是两层规则的意义。
    expect(
      _ids(ReviewWordSelector.selectTwoLayer(words, limit: 4)),
      <int>[1, 3, 2, 4],
    );
  });

  test('两层选词：10 个词按 40/60 分配，第一层 4 个第二层 6 个', () {
    // 难度 1~10 的十个词，都没复习过、释义一致。
    final words = <Word>[
      for (var i = 1; i <= 10; i++) _word(i, 'w$i', difficulty: i),
    ];

    // limit=10 → 第一层 ceil(10×0.4)=4，按难度降序取 [10,9,8,7]；
    // 第二层排除后剩难度 1~6 的词，按第二层规则（复习时间全空→含义全同→
    // 难度降序）排成 [6,5,4,3,2,1]。
    // 合并 [10,9,8,7, 6,5,4,3,2,1]。
    expect(
      _ids(ReviewWordSelector.selectTwoLayer(words, limit: 10)),
      <int>[10, 9, 8, 7, 6, 5, 4, 3, 2, 1],
    );
  });

  test('两层选词：exclude 参数对两层都生效', () {
    final words = <Word>[
      for (var i = 1; i <= 5; i++) _word(i, 'w$i', difficulty: i),
    ];

    // 排除 {5} 后第一层难度降序最高的是 4、3，取前 ceil(5×0.4)=2 个 → [4, 3]；
    // 第二层排除 {4,3,5} 后剩 [1,2]，配额 3 但只够取 2 个 → [2, 1]。
    // 合并 [4, 3, 2, 1]。
    expect(
      _ids(
        ReviewWordSelector.selectTwoLayer(
          words,
          limit: 5,
          exclude: <int>{5},
        ),
      ),
      <int>[4, 3, 2, 1],
    );
  });

  test('两层选词：词库不足目标时返回全部，不报错', () {
    final words = <Word>[
      _word(1, 'a', difficulty: 1),
      _word(2, 'b', difficulty: 2),
    ];

    // limit=10 但只有 2 个词：第一层 ceil(10×0.4)=4，但只能取到 2 个；
    // 第二层候选已被第一层抽空，取 0 个。合并 [2, 1]（难度降序）。
    expect(
      _ids(ReviewWordSelector.selectTwoLayer(words, limit: 10)),
      <int>[2, 1],
    );
  });

  test('两层选词：目标非正数或词库为空时返回空列表', () {
    final words = <Word>[_word(1, 'a')];
    expect(ReviewWordSelector.selectTwoLayer(words, limit: 0), isEmpty);
    expect(ReviewWordSelector.selectTwoLayer(words, limit: -3), isEmpty);
    expect(
      ReviewWordSelector.selectTwoLayer(const <Word>[], limit: 5),
      isEmpty,
    );
  });

  test('两层选词不会改变调用方持有的原始列表顺序', () {
    final words = <Word>[
      _word(3, 'c', difficulty: 3),
      _word(1, 'a', difficulty: 1),
      _word(2, 'b', difficulty: 2),
    ];
    ReviewWordSelector.selectTwoLayer(words, limit: 3);
    // 排序发生在内部副本上，外部列表必须原封不动。
    expect(_ids(words), <int>[3, 1, 2]);
  });
}
