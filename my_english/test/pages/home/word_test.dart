// flutter_test 提供普通单元测试能力。
import 'package:flutter_test/flutter_test.dart';
// 引入 Meaning DTO。
import 'package:my_english/models/meaning.dart';
// 引入 Word DTO。
import 'package:my_english/models/word.dart';

///
/// 验证 MethodChannel Map 与 Word/Meaning 强类型模型的转换。
void main() {
  // fromMap 应完整读取 README 当前使用的字段。
  test('Word.fromMap parses nested meanings and nullable difficulty', () {
    // 固定时间戳便于精确断言。
    final createdAt = DateTime(2026, 3, 18).millisecondsSinceEpoch;
    // 构造与 Android SQLite 返回结构相同的 Map。
    final word = Word.fromMap(<Object?, Object?>{
      'id': 1,
      'spelling': 'able',
      'difficulty': null,
      'created_at': createdAt,
      'updated_at': createdAt,
      'meanings': <Object?>[
        <Object?, Object?>{
          'id': 10,
          'word_id': 1,
          'index': 1,
          'pos': 'adj.',
          'definitions': <Object?>['能做……的', '有才干的'],
        },
      ],
    });

    // Word 主字段应正确转换。
    expect(word.id, 1);
    expect(word.spelling, 'able');
    // README 数字空值统一收窄为 0。
    expect(word.difficulty, 0);
    expect(word.createdAt?.millisecondsSinceEpoch, createdAt);
    // 嵌套 Meaning 数量与内容正确。
    expect(word.meanings, hasLength(1));
    final meaning = word.meanings.single;
    expect(meaning.wordId, 1);
    expect(meaning.pos, 'adj.');
    expect(meaning.definitions, <String>['能做……的', '有才干的']);
  });

  // toMap 为未来 SQLite CRUD 保留所有 Word/Meaning 字段。
  test('Word.toMap keeps nested meaning data', () {
    // 构造包含一个 Meaning 的 Word。
    final word = Word(
      id: 2,
      spelling: 'animal',
      difficulty: 8,
      meanings: const <Meaning>[
        Meaning(
          id: 20,
          wordId: 2,
          index: 1,
          pos: 'n.',
          definitions: <String>['动物'],
        ),
      ],
    );
    // 转成平台通道 Map。
    final map = word.toMap();

    // 数值难度无上限，不应被限制在旧的 1—5。
    expect(map['difficulty'], 8);
    // 嵌套 Meaning 仍然存在。
    final meanings = map['meanings']! as List<Map<String, Object?>>;
    expect(meanings.single['definitions'], <String>['动物']);
  });

  test('Word keeps README phonetics and inflection arrays', () {
    final word = Word.fromMap(<Object?, Object?>{
      'spelling': 'good',
      'phonetic_uk': 'gʊd',
      'phonetic_us': 'gʊd',
      'plural': <String>[],
      'third_person_singular': <String>[],
      'gerund': <String>[],
      'past_tense': <String>[],
      'past_participle': <String>[],
      'comparative': <String>['better'],
      'superlative': <String>['best'],
      // 错误日期与 0 都表示空日期。
      'reviewed_at': 'not-a-date',
      'created_at': 0,
    });

    expect(word.phoneticUk, 'gʊd');
    expect(word.comparative, <String>['better']);
    expect(word.superlative, <String>['best']);
    expect(word.reviewedAt, isNull);
    expect(word.createdAt, isNull);
    expect(word.toMap()['difficulty'], 0);
    expect(word.toMap()['comparative'], <String>['better']);
  });
}
