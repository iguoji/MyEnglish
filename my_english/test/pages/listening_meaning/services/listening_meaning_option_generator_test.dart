// flutter_test 提供纯 Dart 规则测试使用的 test 和 expect。
import 'package:flutter_test/flutter_test.dart';

// 引入单词与释义模型，构造首页词库测试数据。
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';
// 引入需要验证的候选项生成服务。
import 'package:my_english/pages/listening_meaning/services/listening_meaning_option_generator.dart';

///
/// 验证听音辨义候选项的数量、拼写形态和词库相似度排序。
void main() {
  test('word distractors keep length and use plausible letter changes', () {
    // ability 有足够的同长度换位、元音和辅音替换结果。
    final distractors = ListeningMeaningOptionGenerator.buildWordDistractors(
      correct: 'ability',
      sourceWords: <Word>[
        Word(spelling: 'ability'),
        Word(spelling: 'abandon'),
      ],
    );

    // 页面会再加上一个正确项，因此服务必须精确返回三个干扰项。
    expect(distractors, hasLength(3));
    // 所有候选项必须唯一。
    expect(distractors.toSet(), hasLength(3));
    // 不能把正确答案放进干扰列表。
    expect(distractors, isNot(contains('ability')));
    // 常见的中间字母交换结果会被优先保留。
    expect(distractors, contains('abliity'));
    // 条件允许时三个干扰项均与正确单词字母数相同。
    expect(
      distractors.every((item) => item.length == 'ability'.length),
      isTrue,
    );
    // 不再出现数字、中文后缀或其他明显非英文字符。
    expect(
      distractors.every((item) => RegExp(r'^[A-Za-z]+$').hasMatch(item)),
      isTrue,
    );
  });

  test('word distractors fall back to similarly sized source words', () {
    // 非英文正确值无法生成合法字母变体，因此会检验词库回退分支。
    final distractors = ListeningMeaningOptionGenerator.buildWordDistractors(
      correct: '123',
      sourceWords: <Word>[
        Word(spelling: 'cat'),
        Word(spelling: 'bat'),
        Word(spelling: 'mat'),
        Word(spelling: 'longer'),
      ],
    );

    // 三个与目标同长度的真实词库单词应先于 longer。
    expect(distractors, <String>['cat', 'bat', 'mat']);
  });

  test('definition distractors draw only from other words and cap at count', () {
    // 词库里同时给出正确词与其他词：候选只能来自其他词的释义，随机、至多 count。
    Word w(String s, List<String> defs) => Word(
          spelling: s,
          meanings: <Meaning>[for (final d in defs) Meaning(pos: 'n.', definition: d)],
        );
    final sourceWords = <Word>[
      w('ability', <String>['能力', '才能']), // 当前正确词，两个含义都不得当混淆项
      w('energy', <String>['能量']),
      w('strength', <String>['实力']),
      w('capable', <String>['可以完成任务的']),
    ];

    // 多次抽样，验证每一次都只包含其他单词的释义、不含自身含义、数量正确。
    // 页面会传入当前正确词自身的全部含义（能力 / 才能）作排除，这里照做。
    final pooled = <String>{'能量', '实力', '可以完成任务的'};
    for (var i = 0; i < 20; i++) {
      final distractors =
          ListeningMeaningOptionGenerator.buildDefinitionDistractors(
        correct: '能力',
        sourceWords: sourceWords,
        excludeDefinitions: const <String>{'能力', '才能'},
      );
      expect(distractors.toSet().difference(pooled), isEmpty,
          reason: '候选必须全部来自其他单词的释义：$distractors');
      expect(distractors, isNot(contains('能力')));
      expect(distractors, isNot(contains('才能')));
      expect(distractors, hasLength(3));
      expect(distractors.toSet(), hasLength(3));
    }
  });

  test('definition distractors return zero when the bank holds only one word', () {
    // 用户只录入 1 个单词就开始复习：没有其他词可当混淆项。
    final distractors = ListeningMeaningOptionGenerator.buildDefinitionDistractors(
      correct: '能力',
      sourceWords: <Word>[
        Word(
          spelling: 'ability',
          meanings: <Meaning>[Meaning(pos: 'n.', definition: '能力')],
        ),
      ],
    );

    // 没有混淆项时直接返回空，绝不强行凑够——“不强凑”。
    expect(distractors, isEmpty);
    // count 为 0 也直接返回空。
    expect(
      ListeningMeaningOptionGenerator.buildDefinitionDistractors(
        correct: '能力',
        sourceWords: <Word>[
          Word(spelling: 'a', meanings: <Meaning>[Meaning(pos: 'n.', definition: '能力')]),
          Word(spelling: 'b', meanings: <Meaning>[Meaning(pos: 'n.', definition: '别的')]),
        ],
        count: 0,
      ),
      isEmpty,
    );
  });

  test('definition distractors return fewer than count when bank is tiny', () {
    // 词库只有 2 个其他释义时，只能给 2 个混淆项（不补齐到 3）。
    final distractors = ListeningMeaningOptionGenerator.buildDefinitionDistractors(
      correct: '能力',
      sourceWords: <Word>[
        Word(spelling: 'ability', meanings: <Meaning>[Meaning(pos: 'n.', definition: '能力')]),
        Word(spelling: 'energy', meanings: <Meaning>[Meaning(pos: 'n.', definition: '能量')]),
        Word(spelling: 'strength', meanings: <Meaning>[Meaning(pos: 'n.', definition: '实力')]),
      ],
    );
    expect(distractors.toSet(), equals(<String>{'能量', '实力'}));
    expect(distractors, isNot(contains('能力')));
  });

  test('definition distractors never contain the current word own meanings', () {
    final sourceWords = <Word>[
      Word(spelling: 'a', meanings: <Meaning>[Meaning(pos: 'n.', definition: '能力')]),
      Word(spelling: 'b', meanings: <Meaning>[Meaning(pos: 'n.', definition: '能量')]),
      Word(spelling: 'c', meanings: <Meaning>[Meaning(pos: 'n.', definition: '实力')]),
      Word(spelling: 'd', meanings: <Meaning>[Meaning(pos: 'n.', definition: '状态')]),
    ];
    for (var i = 0; i < 20; i++) {
      final correct = '实力';
      final distrac = ListeningMeaningOptionGenerator.buildDefinitionDistractors(
        correct: correct,
        sourceWords: sourceWords,
      );
      expect(distrac, isNot(contains('实力')));
      expect(distrac.toSet().difference(<String>{'能力', '能量', '状态'}), isEmpty);
      expect(distrac, hasLength(3));
    }
  });

  test('replacement definition helper returns a fresh candidate when pool allows', () {
    final sourceWords = <Word>[
      Word(spelling: 'a', meanings: <Meaning>[Meaning(pos: 'n.', definition: '能力')]),
      Word(spelling: 'b', meanings: <Meaning>[Meaning(pos: 'n.', definition: '能量')]),
      Word(spelling: 'c', meanings: <Meaning>[Meaning(pos: 'n.', definition: '实力')]),
      Word(spelling: 'd', meanings: <Meaning>[Meaning(pos: 'n.', definition: '状态')]),
      Word(spelling: 'e', meanings: <Meaning>[Meaning(pos: 'n.', definition: '目标')]),
      Word(spelling: 'f', meanings: <Meaning>[Meaning(pos: 'n.', definition: '方式')]),
    ];
    final initial = ListeningMeaningOptionGenerator.buildDefinitionDistractors(
      correct: '能量',
      sourceWords: sourceWords,
    );
    final replacement =
        ListeningMeaningOptionGenerator.findReplacementDefinitionDistractor(
          correct: '能量',
          sourceWords: sourceWords,
          excluded: <String>['能量', ...initial],
        );
    expect(replacement, isNotNull);
    expect(initial, isNot(contains(replacement)));
    expect(replacement, isNot('能量'));
  });

  test('definition distractors cap at count even with a rich pool', () {
    final distractors = ListeningMeaningOptionGenerator.buildDefinitionDistractors(
      correct: '能力',
      sourceWords: <Word>[
        for (var i = 0; i < 30; i++)
          Word(spelling: 'word$i', meanings: <Meaning>[Meaning(pos: 'n.', definition: '含义$i')]),
      ],
    );
    expect(distractors, hasLength(3));
    expect(distractors.toSet(), hasLength(3));
  });

}
