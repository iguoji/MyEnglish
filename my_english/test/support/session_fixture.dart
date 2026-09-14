import 'dart:math';

import 'package:my_english/models/session.dart';
import 'package:my_english/models/session_question.dart';
import 'package:my_english/models/session_record.dart';
import 'package:my_english/models/word.dart';
import 'package:my_english/pages/review/services/question_builder.dart';

///
/// 测试用的会话装配件：按真实规则给词表编一份试卷，再组装成能直接喂给页面的会话。
///
/// 为什么需要它：一局练习在数据库里是**四层**——会话 → 大题 → 小题 → 考察对象，
/// 另外还有开局那一刻的词库快照。页面读的是这几层（`session.groups` 与
/// `session.snapshotWords`），`items` 只是给「这一局有几题」用的便宜投影。
/// 测试里手拼会话时只塞 `items` 是不够的——页面会看到一份空试卷。
///
/// 编题规则直接调生产代码的 [ReviewQuestionBuilder]，不另写一套，
/// 免得试卷形状和真实开局走偏。
///

/// 按真实规则编题，并补齐大题/小题编号与「当前小题」指针。
///
/// [pinnedDistractors] 用来把「某道题用哪几个干扰词」钉死，键是题目的内容
/// （看义选词就是那道中文释义）。候选平时是开局后按词库现算的、带随机性，
/// 用例要断言「点错的是第几项」就必须先知道候选是哪些词；写进题目快照后
/// `QuestionOptions` 见到「非空候选 + 凑满四项」会直接采用，不再现算。
List<SessionMainQuestion> buildPaper(
  ReviewModule module,
  List<Word> words, {
  int? seed,
  Map<String, List<String>>? pinnedDistractors,
}) {
  final raw = ReviewQuestionBuilder.build(
    module,
    words,
    random: seed == null ? null : Random(seed),
  );
  final paper = <SessionMainQuestion>[];
  // 小题编号在整个会话里连续递增，和原生插库时的自增主键一致。
  var questionId = 1;
  for (final group in raw) {
    final groupId = paper.length + 1;
    final questions = <SessionSubQuestion>[];
    for (final item in group['questions']! as List<Object?>) {
      final map = Map<Object?, Object?>.from(item! as Map);
      final content = (map['content']! as List).first as String;
      final pinned = pinnedDistractors?[content.trim()];
      questions.add(
        SessionSubQuestion.fromMap(<Object?, Object?>{
          ...map,
          'id': questionId++,
          'main_question_id': groupId,
          'question_no': questions.length + 1,
          // 只有钉死候选时才写进题目快照；没钉的题保持 null，让页面照常现算。
          'distractors': ?pinned,
        }),
      );
    }
    paper.add(
      SessionMainQuestion(
        id: groupId,
        no: groupId,
        // 第一遍是大题的「进行中」阶段，后面几遍为 0。
        phase: paper.isEmpty ? 1 : 0,
        retryCount: 0,
        currentSubQuestionId: questions.first.id,
        questions: questions,
      ),
    );
  }
  return paper;
}

///
/// 按模块把试卷投影成 `items`，形状与原生 `readSession` 完全一致。
///
List<Object?> buildItems(ReviewModule module, List<SessionMainQuestion> paper) {
  // 一题只认第一个考察对象的单词主键，与原生 `firstDetail` 一致。
  int wordId(SessionSubQuestion question) => question.details.first.wordId;
  final flat = <SessionSubQuestion>[
    for (final group in paper) ...group.questions,
  ];
  switch (module) {
    case ReviewModule.listeningMeaning:
      // 每个单词一个大题，投影就是每个大题的首个单词。
      return <Object?>[
        for (final group in paper) wordId(group.questions.first),
      ];
    case ReviewModule.meaningMatch:
      // 每一轮一个嵌套数组，轮内是 [单词编号, 含义编号] 数对。
      return <Object?>[
        for (final group in paper)
          <Object?>[
            for (final question in group.questions)
              <Object?>[wordId(question), question.details.first.meaningId],
          ],
      ];
    case ReviewModule.meaningWordChoice:
      // 看义选词没有天然的单词顺序，投影记小题编号。
      return <Object?>[for (final question in flat) question.id];
    case ReviewModule.listening:
    case ReviewModule.spellingReinforcement:
      return <Object?>[for (final question in flat) wordId(question)];
  }
}

///
/// 组装一局会话，含完整试卷与开局词库快照。
///
/// [seed] 固定随机源时，随机相关的题型（词义连连分组、看义选词干扰项）可复现。
///
Session buildSession({
  required int id,
  required ReviewModule module,
  required List<Word> words,
  required String date,
  SessionKind kind = SessionKind.daily,
  SessionStatus status = SessionStatus.active,
  int? wordSetId = 1,
  int cursor = 0,
  int elapsed = 0,
  List<SessionRecord> records = const <SessionRecord>[],
  int? seed,
  Map<String, List<String>>? pinnedDistractors,
}) {
  final paper = buildPaper(
    module,
    words,
    seed: seed,
    pinnedDistractors: pinnedDistractors,
  );
  return Session(
    id: id,
    module: module,
    kind: kind,
    status: status,
    wordSetId: wordSetId,
    items: List<Object?>.unmodifiable(buildItems(module, paper)),
    cursor: cursor,
    elapsed: elapsed,
    date: date,
    createdAt: DateTime.now(),
    groups: paper,
    snapshotWords: List<Word>.unmodifiable(words),
    records: records,
  );
}
