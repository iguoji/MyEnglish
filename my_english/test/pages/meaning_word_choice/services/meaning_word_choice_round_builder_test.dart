// dart:math 提供固定随机种子，让候选词的干扰项抽取在测试里可复现。
import 'dart:math';

// flutter_test 提供 test / expect 等断言工具。
import 'package:flutter_test/flutter_test.dart';

// 被测构建服务与依赖模型。
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';
import 'package:my_english/pages/meaning_word_choice/services/meaning_word_choice_round_builder.dart';

///
/// 构造一个带唯一含义主键的单词。
///
/// [id] 单词主键；[meaningId] 该释义在 SQLite 里的主键（看义选词按它出题）。
///
Word _word(
  int id,
  int meaningId,
  String spelling,
  String definition, {
  String pos = 'n.',
}) => Word(
  id: id,
  spelling: spelling,
  meanings: <Meaning>[Meaning(id: meaningId, pos: pos, definition: definition)],
);

void main() {
  group('buildRoundsFromMeaningIds', () {
    test('按数据列表还原轮次，多词共享释义合并成一道题', () {
      // eat 与 feed 都有「吃」，apple 有「苹果」。
      final words = <Word>[
        _word(1, 101, 'apple', '苹果'),
        _word(2, 102, 'eat', '吃', pos: 'v.'),
        _word(3, 103, 'feed', '吃', pos: 'v.'),
      ];

      final rounds = MeaningWordChoiceRoundBuilder.buildRoundsFromMeaningIds(
        <int>[102, 101],
        words,
      );

      // 两道题，顺序与数据列表一致。
      expect(rounds, hasLength(2));
      // 第一题「吃」：代表含义主键是数据列表里的 102，匹配 eat 与 feed。
      expect(rounds[0].meaningId, 102);
      expect(rounds[0].definition, '吃');
      expect(rounds[0].matchIds, <int>[2, 3]);
      expect(rounds[0].posGroup, <String>['v.']);
      // 第二题「苹果」：只匹配 apple。
      expect(rounds[1].meaningId, 101);
      expect(rounds[1].definition, '苹果');
      expect(rounds[1].matchIds, <int>[1]);
    });

    test('同一释义出现在不同词性下时，词性合并进一个数组', () {
      // hi 标 int.，hello 标 n.，但中文都是「你好」。
      final words = <Word>[
        _word(1, 201, 'hi', '你好', pos: 'int.'),
        _word(2, 202, 'hello', '你好'),
      ];

      final rounds = MeaningWordChoiceRoundBuilder.buildRoundsFromMeaningIds(
        <int>[201],
        words,
      );

      expect(rounds, hasLength(1));
      // 两个词都算这一轮的正确答案。
      expect(rounds[0].matchIds, <int>[1, 2]);
      // 词性按字典序合并，保证展示稳定。
      expect(rounds[0].posGroup, <String>['int.', 'n.']);
    });

    test('数据列表里的含义已不在会话词表中时，这一轮被安全跳过', () {
      final words = <Word>[_word(1, 301, 'apple', '苹果')];

      // 302 这个含义主键在词表里不存在（词被删了）。
      final rounds = MeaningWordChoiceRoundBuilder.buildRoundsFromMeaningIds(
        <int>[301, 302],
        words,
      );

      // 只保留能对上号的轮次，不让整局崩掉。
      expect(rounds, hasLength(1));
      expect(rounds[0].definition, '苹果');
    });

    test('数据列表里若出现同释义的两个含义主键，模型层已去重，只会出一道题', () {
      // 同一单词下两条释义文本相同：Word 构造时按词性组内去重，
      // 重复文本的第二个含义主键不会进入 allMeanings，构建器自然跳过它。
      final word = Word(
        id: 1,
        spelling: 'apple',
        meanings: <Meaning>[
          Meaning(id: 401, pos: 'n.', definition: '苹果'),
          Meaning(id: 402, pos: 'n.', definition: '苹果'),
        ],
      );

      final rounds = MeaningWordChoiceRoundBuilder.buildRoundsFromMeaningIds(
        <int>[401, 402],
        <Word>[word],
      );

      // 只出一道「苹果」，答案仍然是 apple。
      expect(rounds, hasLength(1));
      expect(rounds[0].definition, '苹果');
      expect(rounds[0].matchIds, <int>[1]);
    });
  });

  group('buildCandidates', () {
    test('匹配词全部上阵，不足四个时用不含当前含义的词补齐', () {
      final words = <Word>[
        _word(1, 101, 'apple', '苹果'),
        _word(2, 102, 'banana', '香蕉'),
        _word(3, 103, 'cat', '猫'),
        _word(4, 104, 'eat', '吃', pos: 'v.'),
        _word(5, 105, 'feed', '吃', pos: 'v.'),
      ];
      final rounds = MeaningWordChoiceRoundBuilder.buildRoundsFromMeaningIds(
        <int>[104],
        words,
      );

      // 「吃」有两个匹配词（eat/feed），补 2 个干扰词凑满 4 个。
      final candidates = MeaningWordChoiceRoundBuilder.buildCandidates(
        round: rounds[0],
        words: words,
        random: Random(1),
      );

      expect(candidates, hasLength(4));
      // 两个匹配词都必须是正确答案。
      expect(
        candidates
            .where((candidate) => candidate.isMatch)
            .map((candidate) => candidate.wordId)
            .toSet(),
        <int>{4, 5},
      );
      // 干扰词不能是含「吃」含义的单词。
      for (final candidate in candidates.where((item) => !item.isMatch)) {
        final spelling = words
            .firstWhere((word) => word.id == candidate.wordId)
            .spelling;
        expect(<String>{'apple', 'banana', 'cat'}, contains(spelling));
      }
    });

    test('匹配词超过四个时突破上限，不做截断', () {
      // 五个单词共享「吃」这一个释义。
      final words = <Word>[
        for (var id = 1; id <= 5; id += 1)
          _word(id, 500 + id, 'word$id', '吃', pos: 'v.'),
      ];
      final rounds = MeaningWordChoiceRoundBuilder.buildRoundsFromMeaningIds(
        <int>[501],
        words,
      );

      final candidates = MeaningWordChoiceRoundBuilder.buildCandidates(
        round: rounds[0],
        words: words,
        random: Random(1),
      );

      // 全部匹配词都必须出现，哪怕超过默认的 4 个。
      expect(candidates, hasLength(5));
      expect(candidates.map((candidate) => candidate.wordId).toSet(), <int>{
        1,
        2,
        3,
        4,
        5,
      });
    });

    test('候选按字母升序排列，同一拼写用主键兜底', () {
      final words = <Word>[
        _word(1, 101, 'pear', '梨'),
        _word(2, 102, 'apple', '苹果'),
        _word(3, 103, 'egg', '蛋'),
        _word(4, 104, 'banana', '香蕉'),
        _word(5, 105, 'carrot', '胡萝卜'),
      ];
      final rounds = MeaningWordChoiceRoundBuilder.buildRoundsFromMeaningIds(
        <int>[101],
        words,
      );

      final candidates = MeaningWordChoiceRoundBuilder.buildCandidates(
        round: rounds[0],
        words: words,
        random: Random(1),
      );

      // 1 个匹配词（pear）+ 3 个干扰词 = 4 个候选。
      expect(candidates, hasLength(4));
      // 匹配词永远在场。
      expect(
        candidates
            .where((candidate) => candidate.isMatch)
            .map((candidate) => candidate.wordId)
            .toList(),
        <int>[1],
      );
      // 候选拼写严格按字母升序（选哪几个干扰词随机，但顺序永远确定）。
      final spellings = <String>[
        for (final candidate in candidates)
          words.firstWhere((word) => word.id == candidate.wordId).spelling,
      ];
      for (var index = 1; index < spellings.length; index += 1) {
        expect(spellings[index - 1].compareTo(spellings[index]), lessThan(0));
      }
    });

    test('会话里凑不齐干扰词时少几个，不引入会话外的保底词', () {
      // 只有两个单词：一个是匹配词，另一个是不含当前含义的词。
      final words = <Word>[
        _word(1, 101, 'apple', '苹果'),
        _word(2, 102, 'banana', '香蕉'),
      ];
      final rounds = MeaningWordChoiceRoundBuilder.buildRoundsFromMeaningIds(
        <int>[101],
        words,
      );

      final candidates = MeaningWordChoiceRoundBuilder.buildCandidates(
        round: rounds[0],
        words: words,
        random: Random(1),
      );

      // 只有 2 个候选：apple + banana，不会凭空多出第三个词。
      expect(candidates, hasLength(2));
      expect(candidates.map((candidate) => candidate.wordId).toSet(), <int>{
        1,
        2,
      });
    });
  });
}
