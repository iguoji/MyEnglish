import 'model_value_parser.dart';

/// 题目关联的原始词义。合并显示的一个含义可以关联多条记录。
class SessionQuestionDetail {
  const SessionQuestionDetail({required this.wordId, this.meaningId});
  final int wordId;
  final int? meaningId;

  factory SessionQuestionDetail.fromMap(Map<Object?, Object?> map) =>
      SessionQuestionDetail(
        wordId: readOptionalInt(map['word_id'], '题目单词编号')!,
        meaningId: readOptionalInt(map['meaning_id'], '题目含义编号'),
      );
}

/// 一次实际出现的小题，重复出题也拥有独立编号。
class SessionSubQuestion {
  const SessionSubQuestion({
    required this.id,
    required this.mainQuestionId,
    required this.no,
    required this.type,
    required this.contentType,
    required this.answerType,
    required this.content,
    required this.answers,
    required this.details,
    this.distractors,
    this.optionOrder,
    this.usedSeconds = 0,
  });

  final int id;
  final int mainQuestionId;
  final int no;
  final int type;
  final int contentType;
  final int answerType;
  final List<String> content;
  final List<String> answers;

  /// 这道题的干扰项；null 表示还没生成，空数组用于没有候选的题型。
  final List<String>? distractors;

  /// 开局时排好的四个候选顺序（答案已放在「洗牌发牌」定下的那一格）。
  ///
  /// 旧版本开的局没有这一项，为 null。
  final List<String>? optionOrder;
  final List<SessionQuestionDetail> details;
  final int usedSeconds;

  Set<int> get wordIds => details.map((detail) => detail.wordId).toSet();

  /// 这道题已经定好的四个候选，按屏幕上 A、B、C、D 的顺序。
  ///
  /// 本局开局时排好的顺序原样使用，恢复会话时一模一样；旧版本开的局只存了
  /// 干扰项，沿用当时「按字母 / 字符编码排序」的老规则还原。还没生成干扰项、
  /// 或者存下的内容凑不成四个不同候选时返回 null，交给候选服务重新准备。
  List<String>? get presetOptions {
    final distractors = this.distractors;
    if (distractors == null) return null;
    final english = answerType == 1;
    final pool = <String>[...answers, ...distractors];
    String key(String text) =>
        english ? text.trim().toLowerCase() : text.trim();
    final keys = pool.map(key).toSet();
    if (pool.length != 4 || keys.length != 4) return null;
    final order = optionOrder;
    if (order != null &&
        order.length == 4 &&
        order.map(key).toSet().containsAll(keys) &&
        order.every((text) => pool.contains(text))) {
      return List<String>.unmodifiable(order);
    }
    return sortQuestionOptions(pool, english: english);
  }

  factory SessionSubQuestion.fromMap(Map<Object?, Object?> map) =>
      SessionSubQuestion(
        id: readOptionalInt(map['id'], '小题编号')!,
        mainQuestionId: readOptionalInt(map['main_question_id'], '大题编号')!,
        no: readIntOrFallback(map['question_no'], fallback: 1),
        type: readIntOrFallback(map['question_type'], fallback: 0),
        contentType: readIntOrFallback(map['content_type'], fallback: 1),
        answerType: readIntOrFallback(map['answer_type'], fallback: 0),
        content: readStringList(map['content'], '题目内容'),
        answers: readStringList(map['answers'], '题目答案'),
        distractors: map['distractors'] == null
            ? null
            : readStringList(map['distractors'], '混淆选项'),
        optionOrder: map['options'] == null
            ? null
            : readStringList(map['options'], '候选顺序'),
        usedSeconds: readIntOrFallback(map['used_seconds'], fallback: 0),
        details: <SessionQuestionDetail>[
          for (final raw in map['details'] as List? ?? const [])
            SessionQuestionDetail.fromMap(
              Map<Object?, Object?>.from(raw as Map),
            ),
        ],
      );
}

/// 大题负责阶段和整题重试，所有小题共享这一遍的尝试序号。
class SessionMainQuestion {
  const SessionMainQuestion({
    required this.id,
    required this.no,
    required this.phase,
    required this.retryCount,
    required this.questions,
    this.currentSubQuestionId,
  });
  final int id;
  final int no;
  final int phase;
  final int retryCount;
  final int? currentSubQuestionId;
  final List<SessionSubQuestion> questions;
  int get attemptNo => retryCount + 1;

  factory SessionMainQuestion.fromMap(Map<Object?, Object?> map) =>
      SessionMainQuestion(
        id: readOptionalInt(map['id'], '大题编号')!,
        no: readIntOrFallback(map['question_no'], fallback: 1),
        phase: readIntOrFallback(map['phase'], fallback: 0),
        retryCount: readIntOrFallback(map['retry_count'], fallback: 0),
        currentSubQuestionId: readOptionalInt(
          map['current_sub_question_id'],
          '当前小题',
        ),
        questions: <SessionSubQuestion>[
          for (final raw in map['questions'] as List? ?? const [])
            SessionSubQuestion.fromMap(Map<Object?, Object?>.from(raw as Map)),
        ],
      );
}

/// 旧版本的候选排序：英文忽略大小写按字母排列，中文按字符编码排列。
///
/// 现在只用来还原旧版本开的局（它们没有保存候选顺序）；新局的顺序在开局时
/// 按「洗牌发牌」排好并保存，见 [SessionSubQuestion.optionOrder]。
List<String> sortQuestionOptions(
  Iterable<String> values, {
  required bool english,
}) {
  final seen = <String>{};
  final result = <String>[
    for (final value in values.map((value) => value.trim()))
      if (value.isNotEmpty && seen.add(english ? value.toLowerCase() : value))
        value,
  ];
  result.sort((a, b) {
    final compared = english
        ? a.toLowerCase().compareTo(b.toLowerCase())
        : a.compareTo(b);
    return compared == 0 ? a.compareTo(b) : compared;
  });
  return List<String>.unmodifiable(result);
}
