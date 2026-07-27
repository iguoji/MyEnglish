// flutter_test 提供纯 Dart 规则测试使用的 test 和 expect。
import 'package:flutter_test/flutter_test.dart';

// 引入单词与释义模型，构造首页词库测试数据。
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';
// 引入需要验证的候选项生成服务。
import 'package:my_english/pages/dictation/services/dictation_option_generator.dart';

/// 验证默写候选项的数量、拼写形态和词库相似度排序。
void main() {
  test('word distractors keep length and use plausible letter changes', () {
    // ability 有足够的同长度换位、元音和辅音替换结果。
    final distractors = DictationOptionGenerator.buildWordDistractors(
      correct: 'ability',
      sourceWords: const <Word>[
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
    final distractors = DictationOptionGenerator.buildWordDistractors(
      correct: '123',
      sourceWords: const <Word>[
        Word(spelling: 'cat'),
        Word(spelling: 'bat'),
        Word(spelling: 'mat'),
        Word(spelling: 'longer'),
      ],
    );

    // 三个与目标同长度的真实词库单词应先于 longer。
    expect(distractors, <String>['cat', 'bat', 'mat']);
  });

  test('definition distractors prefer same-length similar source meanings', () {
    // 词库中同时放入同字数和不同字数的释义。
    const sourceWords = <Word>[
      Word(
        spelling: 'ability',
        meanings: <Meaning>[
          Meaning(index: 1, pos: 'n.', definitions: <String>['能力', '才能']),
        ],
      ),
      Word(
        spelling: 'energy',
        meanings: <Meaning>[
          Meaning(index: 1, pos: 'n.', definitions: <String>['能量']),
        ],
      ),
      Word(
        spelling: 'strength',
        meanings: <Meaning>[
          Meaning(index: 1, pos: 'n.', definitions: <String>['实力']),
        ],
      ),
      Word(
        spelling: 'capable',
        meanings: <Meaning>[
          Meaning(index: 1, pos: 'adj.', definitions: <String>['可以完成任务的']),
        ],
      ),
    ];
    // 以“能力”作为正确释义进行检索。
    final distractors = DictationOptionGenerator.buildDefinitionDistractors(
      correct: '能力',
      sourceWords: sourceWords,
    );

    // 三个两字释义必须排在长释义之前；其中“能量”和“实力”各只需替换一字。
    expect(distractors, <String>['能量', '实力', '才能']);
  });

  test('tiny definition source still produces three unique distractors', () {
    // 只有正确释义的极小词库无法直接提供三个其他释义。
    final distractors = DictationOptionGenerator.buildDefinitionDistractors(
      correct: '能力',
      sourceWords: const <Word>[
        Word(
          spelling: 'ability',
          meanings: <Meaning>[
            Meaning(index: 1, pos: 'n.', definitions: <String>['能力']),
          ],
        ),
      ],
    );

    // 即使词库不足，界面仍会得到三个不重复且不等于正确值的干扰项。
    expect(distractors, hasLength(3));
    expect(distractors.toSet(), hasLength(3));
    expect(distractors, isNot(contains('能力')));
    // 优先的人工回退仍保持和正确释义相同的字数。
    expect(distractors.every((item) => item.runes.length == 2), isTrue);
  });
}
