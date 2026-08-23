import 'package:flutter_test/flutter_test.dart';
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';
import 'package:my_english/pages/review/services/review_word_selector.dart';

///
/// 构造一个用于排序断言的单词。
///
/// @param  int  id 主键，也是最后一层兜底比较依据。
/// @param  String  spelling 英文拼写。
/// @param  `List<String>`  definitions 中文释义列表。
/// @param  int  difficulty 当前难度。
/// @param  DateTime?  reviewedAt 最近复习时间；null 表示从未复习。
/// @return Word 组装好的测试单词。
///
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
///
/// @param  `List<Word>`  words 选词结果。
/// @return `List<int>` 主键顺序。
///
List<int> _ids(List<Word> words) => words.map((word) => word.id!).toList();

///
/// 验证复习选词规则的六层比较顺序与补词时的排除能力。
///
/// @return void
///
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
}
