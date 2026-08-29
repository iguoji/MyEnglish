// flutter_test 提供普通单元测试能力。
import 'package:flutter_test/flutter_test.dart';
// 引入 Meaning DTO。
import 'package:my_english/models/meaning.dart';
// 引入 Word DTO。
import 'package:my_english/models/word.dart';

///
/// 验证 MethodChannel Map 与 Word/Meaning 强类型模型的转换（v2.0 结构）。
///
/// 2.0 起一行就是一条释义：Meaning 只带单条 definition，
/// 不再有旧版的 definitions 数组、音标与词形字段。
void main() {
  // fromMap 应完整读取 README 当前使用的字段。
  test('Word.fromMap parses nested meanings and nullable difficulty', () {
    // 固定时间戳便于精确断言。
    final createdAt = DateTime(2026, 3, 18).millisecondsSinceEpoch;
    // 构造与 Android SQLite 返回结构相同的 Map（释义一行一条）。
    final word = Word.fromMap(<Object?, Object?>{
      'id': 1,
      'spelling': 'able',
      'difficulty': null,
      'confusions': <Object?>['cable'],
      'syllables': <Object?>['a', 'ble'],
      'created_at': createdAt,
      'updated_at': createdAt,
      'meanings': <Object?>[
        <Object?, Object?>{
          'id': 10,
          'word_id': 1,
          'pos': 'adj.',
          'definition': '能做……的',
          'confusions': <Object?>['能够'],
        },
        <Object?, Object?>{
          'id': 11,
          'word_id': 1,
          'pos': 'adj.',
          'definition': '有才干的',
        },
      ],
    });

    // Word 主字段应正确转换。
    expect(word.id, 1);
    expect(word.spelling, 'able');
    // README 数字空值统一收窄为 0。
    expect(word.difficulty, 0);
    expect(word.createdAt?.millisecondsSinceEpoch, createdAt);
    // 混淆词与音节数组原样带入。
    expect(word.confusions, <String>['cable']);
    expect(word.syllables, <String>['a', 'ble']);
    // 两条释义都解析出来，并继承外层单词主键作为 word_id 回退值。
    expect(word.allMeanings, hasLength(2));
    final first = word.allMeanings.first;
    expect(first.id, 10);
    expect(first.wordId, 1);
    expect(first.pos, 'adj.');
    expect(first.definition, '能做……的');
    expect(first.confusions, <String>['能够']);
  });

  // fromMap 应按 sort 降序稳定排序释义，与原生返回顺序保持一致。
  test('Word.fromMap sorts meanings by sort value descending', () {
    final word = Word.fromMap(<Object?, Object?>{
      'spelling': 'order',
      'meanings': <Object?>[
        <Object?, Object?>{'id': 2, 'pos': 'n.', 'definition': '后', 'sort': 1},
        <Object?, Object?>{'id': 1, 'pos': 'n.', 'definition': '前', 'sort': 9},
      ],
    });

    // sort 大的排前面：「前」排在「后」之前。
    expect(
      word.allMeanings.map((meaning) => meaning.definition).toList(),
      <String>['前', '后'],
    );
  });

  // toMap 为 SQLite CRUD 保留全部 Word/Meaning 字段，释义摊平回一维。
  test('Word.toMap flattens meanings back to one-dimensional list', () {
    // 构造包含两条释义的 Word。
    final word = Word(
      id: 2,
      spelling: 'animal',
      difficulty: 8,
      meanings: const <Meaning>[
        Meaning(id: 20, wordId: 2, pos: 'n.', definition: '动物'),
        Meaning(id: 21, wordId: 2, pos: 'adj.', definition: '动物的'),
      ],
    );
    // 转成平台通道 Map。
    final map = word.toMap();

    // 数值难度无上限，不应被限制在旧的 1—5。
    expect(map['difficulty'], 8);
    // 嵌套释义是一维数组，每条只有单条 definition。
    final meanings = map['meanings']! as List<Map<String, Object?>>;
    expect(meanings, hasLength(2));
    expect(meanings[0]['definition'], '动物');
    expect(meanings[1]['pos'], 'adj.');
  });

  // 缺拼写的记录无法构成一个可学习的单词，必须明确报错。
  test('Word.fromMap rejects missing spelling', () {
    expect(
      () => Word.fromMap(<Object?, Object?>{'id': 1}),
      throwsA(isA<FormatException>()),
    );
    // 纯空格拼写同样视为无效。
    expect(
      () => Word.fromMap(<Object?, Object?>{'spelling': '   '}),
      throwsA(isA<FormatException>()),
    );
  });
}
