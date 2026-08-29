// flutter_test 提供 test 与 expect，用来验证 Word 编辑后的业务字段。
import 'package:flutter_test/flutter_test.dart';
// 引入需要验证的单词模型与释义模型。
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';

///
/// 验证 Word 模型在 v2.0 下的编辑、复制与含义复杂度比较行为。
///
/// 2.0 结构去掉了分组、音标和词形：一行就是一条释义，分组只存在于展示层。
void main() {
  // 用户只改拼写与释义时，主键、难度等其余字段应原样保留。
  test('edited replaces spelling and meanings but keeps identity', () {
    // 构造一个有主键、难度和一条释义的既有单词。
    final word = Word(
      id: 1,
      spelling: 'old',
      difficulty: 3,
      meanings: const <Meaning>[Meaning(pos: 'n.', definition: '旧')],
    );
    // 表单提交新的拼写与释义列表。
    final edited = word.edited(
      spelling: 'new',
      meanings: const <Meaning>[Meaning(pos: 'n.', definition: '新')],
    );

    // 拼写与释义正常更新。
    expect(edited.spelling, 'new');
    expect(edited.allMeanings.single.definition, '新');
    // 主键与难度不能被编辑操作吞掉。
    expect(edited.id, 1);
    expect(edited.difficulty, 3);
    // 编辑会刷新更新时间，但创建时间保持原样。
    expect(edited.updatedAt, isNotNull);
    expect(edited.createdAt, isNull);
  });

  // copyWith 只替换显式传入的字段，其余保持原值。
  test('copyWith preserves fields that are not replaced', () {
    final word = Word(
      id: 2,
      spelling: 'keep',
      difficulty: 5,
      confusions: const <String>['keep2'],
      syllables: const <String>['keep'],
    );

    // 只换难度，其余字段原样。
    final copied = word.copyWith(difficulty: 1);
    expect(copied.difficulty, 1);
    expect(copied.spelling, 'keep');
    expect(copied.id, 2);
    expect(copied.confusions, <String>['keep2']);
    expect(copied.syllables, <String>['keep']);
  });

  // 含义复杂度先比释义条数，条数相同再比释义总字符数。
  test('compareMeaningComplexityTo compares count then characters', () {
    // 单释义、单字符的简单词。
    final simple = Word(
      id: 1,
      spelling: 'force',
      meanings: const <Meaning>[Meaning(pos: 'n.', definition: '力')],
    );
    // 单释义、多字符的词。
    final verbose = Word(
      id: 2,
      spelling: 'ability',
      meanings: const <Meaning>[
        Meaning(pos: 'n.', definition: '完成某件事情的能力'),
      ],
    );
    // 双释义的词。
    final multi = Word(
      id: 3,
      spelling: 'set',
      meanings: const <Meaning>[
        Meaning(pos: 'n.', definition: '集合'),
        Meaning(pos: 'v.', definition: '放置'),
      ],
    );

    // 释义条数优先：simple（1 条）< multi（2 条）。
    expect(simple.compareMeaningComplexityTo(multi), lessThan(0));
    // 条数相同时比较字符数：simple（1 字）< verbose（9 字）。
    expect(simple.compareMeaningComplexityTo(verbose), lessThan(0));
    expect(verbose.compareMeaningComplexityTo(simple), greaterThan(0));
    // 完全相同的单词比较结果为 0。
    expect(simple.compareMeaningComplexityTo(simple), 0);
  });
}
