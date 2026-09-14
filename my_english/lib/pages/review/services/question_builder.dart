import 'package:flutter/foundation.dart';
import 'dart:math';

import '../../../models/meaning.dart';
import '../../../models/session.dart';
import '../../../models/word.dart';
import 'matching_round_builder.dart';

/// 开局一次性编排完整试卷，页面不会在恢复时重新挑题或拆题。
abstract final class ReviewQuestionBuilder {
  /// 大词库在独立工作线程编题，跳页和点击动画不用等同步遍历完成。
  static Future<List<Map<String, Object?>>> buildAsync(
    ReviewModule module,
    List<Word> words, {
    Random? random,
  }) {
    final size = words.fold<int>(
      0,
      (total, word) => total + word.rawMeanings.length + 1,
    );
    if (size < 256) return Future.value(build(module, words, random: random));
    return compute(_buildPaper, (
      module: module,
      words: words,
      seed: (random ?? Random()).nextInt(0x7fffffff),
    ), debugLabel: 'prepare-study-paper');
  }

  static List<Map<String, Object?>> build(
    ReviewModule module,
    List<Word> words, {
    Random? random,
  }) {
    final source = words.where((word) => word.id != null).toList();
    switch (module) {
      case ReviewModule.listeningMeaning:
        return <Map<String, Object?>>[
          for (final word in source)
            _group(<Map<String, Object?>>[
              _question(100, 1, 1, word.spelling, <String>[
                word.spelling,
              ], _details(word)),
              for (final meaning in _meanings(word, verbOnly: true))
                _question(100, 2, 2, meaning.definition, <String>[
                  meaning.definition,
                ], _details(word, meaning.definition)),
            ]),
        ];
      case ReviewModule.listening:
      case ReviewModule.spellingReinforcement:
        return source.isEmpty
            ? const []
            : <Map<String, Object?>>[
                _group(<Map<String, Object?>>[
                  for (final word in source)
                    _question(
                      module == ReviewModule.listening ? 0 : 300,
                      1,
                      module == ReviewModule.listening ? 0 : 1,
                      word.spelling,
                      module == ReviewModule.listening
                          ? const []
                          : <String>[word.spelling],
                      _details(word),
                    ),
                ]),
              ];
      case ReviewModule.meaningMatch:
        return _matching(source);
      case ReviewModule.meaningWordChoice:
        return _choice(source, random ?? Random());
    }
  }

  static Map<String, Object?> _group(List<Map<String, Object?>> questions) => {
    'questions': questions,
  };

  static Map<String, Object?> _question(
    int type,
    int contentType,
    int answerType,
    String content,
    List<String> answers,
    List<Map<String, Object?>> details,
  ) => {
    'question_type': type,
    'content_type': contentType,
    'answer_type': answerType,
    'content': <String>[content.trim()],
    'answers': answers,
    // 选择题到首次显示时才从混淆字段准备，其他题型不需要干扰选项。
    'distractors': type == 100 || type == 200 ? null : const <String>[],
    'details': details,
  };

  /// 同一个词、同一段中文只练一次；详情保留全部词性记录的编号。
  ///
  /// [verbOnly] 为 true 时（听音辨义）只在动词词性内按释义去重，非动词相同中文
  /// 保留为独立小题；为 false 时（词义连连 / 看义选词）沿用跨词性去重。
  static List<Meaning> _meanings(Word word, {bool verbOnly = false}) {
    if (verbOnly) {
      return <Meaning>[
        for (final meaning in word.verbMergedMeanings)
          if (meaning.id != null && meaning.definition.trim().isNotEmpty)
            meaning,
      ];
    }
    final seen = <String>{};
    return <Meaning>[
      for (final meaning in word.allMeanings)
        if (meaning.id != null &&
            meaning.definition.trim().isNotEmpty &&
            seen.add(meaning.definition.trim()))
          meaning,
    ];
  }

  static List<Map<String, Object?>> _details(Word word, [String? definition]) =>
      definition == null
      ? <Map<String, Object?>>[
          {'word_id': word.id, 'meaning_id': null},
        ]
      : <Map<String, Object?>>[
          for (final meaning in word.rawMeanings)
            if (meaning.id != null &&
                meaning.definition.trim() == definition.trim())
              {'word_id': word.id, 'meaning_id': meaning.id},
        ];

  static List<Map<String, Object?>> _choice(List<Word> words, Random random) {
    final byDefinition = <String, List<Word>>{};
    for (final word in words) {
      for (final meaning in _meanings(word)) {
        (byDefinition[meaning.definition.trim()] ??= <Word>[]).add(word);
      }
    }
    final queues = <String, List<Map<String, Object?>>>{};
    for (final entry in byDefinition.entries) {
      // 相同拼写只有一个可见候选，但关联到所有原始单词，编号不会遗漏。
      final bySpelling = <String, List<Word>>{};
      for (final word in entry.value) {
        (bySpelling[word.spelling.trim().toLowerCase()] ??= <Word>[]).add(word);
      }
      final spellings = bySpelling.keys.toList()..sort();
      final questions = <Map<String, Object?>>[];
      for (var start = 0; start < spellings.length; start += 2) {
        final part = spellings.sublist(start, min(start + 2, spellings.length));
        questions.add(
          _question(
            part.length == 1 ? 100 : 200,
            2,
            1,
            entry.key,
            <String>[for (final key in part) bySpelling[key]!.first.spelling],
            <Map<String, Object?>>[
              for (final key in part)
                for (final word in bySpelling[key]!)
                  ..._details(word, entry.key),
            ],
          ),
        );
      }
      queues[entry.key] = questions;
    }
    final preferredOrder = queues.keys.toList()..shuffle(random);
    final recent = <String>[];
    final output = <Map<String, Object?>>[];
    while (queues.values.any((queue) => queue.isNotEmpty)) {
      final available = preferredOrder
          .where((key) => queues[key]!.isNotEmpty)
          .toList();
      // 优先间隔两题，再退到一题；题库只有一个含义时仍把全部目标练完。
      var eligible = available.where((key) => !recent.contains(key)).toList();
      if (eligible.isEmpty) {
        eligible = available
            .where((key) => recent.isEmpty || key != recent.last)
            .toList();
      }
      if (eligible.isEmpty) eligible = available;
      eligible.sort((a, b) {
        final count = queues[b]!.length.compareTo(queues[a]!.length);
        return count == 0
            ? preferredOrder.indexOf(a).compareTo(preferredOrder.indexOf(b))
            : count;
      });
      final key = eligible.first;
      output.add(queues[key]!.removeAt(0));
      recent.add(key);
      if (recent.length > 2) recent.removeAt(0);
    }
    return output.isEmpty ? const [] : <Map<String, Object?>>[_group(output)];
  }

  static List<Map<String, Object?>> _matching(List<Word> words) {
    final pairs = <Map<String, Object?>>[
      for (final word in words)
        for (final meaning in _meanings(word))
          _question(400, 1, 2, word.spelling, <String>[
            meaning.definition.trim(),
          ], _details(word, meaning.definition)),
    ];
    return MatchingRoundBuilder.build(pairs).map(_group).toList();
  }
}

/// 只传普通数据，工作线程不持有页面、数据库或播放器。
List<Map<String, Object?>> _buildPaper(
  ({ReviewModule module, List<Word> words, int seed}) input,
) => ReviewQuestionBuilder.build(
  input.module,
  input.words,
  random: Random(input.seed),
);
