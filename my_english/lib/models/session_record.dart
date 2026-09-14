///
/// 一次点击的记录。
///
/// 每点一次就写一条，不论对错。正因为「每一次点击都留痕」，
/// 中途退出后的现场可以完整反查出来：
/// - 这一局哪些条目已经答完了 → 有 [result] 为 1 的记录；
/// - 当前这条点错过哪些候选 → [result] 为 0 的那些记录的 [input]。
///
/// 随身听是被动听、没有对错，不写这张表。
class SessionRecord {
  ///
  /// 创建一条会话记录。
  const SessionRecord({
    required this.id,
    required this.wordId,
    required this.meaningId,
    required this.input,
    required this.isCorrect,
    this.questionId,
    this.groupId,
    this.attemptNo = 1,
    this.targetWordIds = const <int>[],
    this.targetMeaningIds = const <int>[],
    this.answerValues = const <String>[],
  });

  /// 具体题号、所属大题及尝试遍次，重复内容不会混用答题记录。
  final int? questionId;
  final int? groupId;
  final int attemptNo;
  final List<int> targetWordIds;
  final List<int> targetMeaningIds;
  final List<String> answerValues;
  List<String> get answers =>
      answerValues.isEmpty ? <String>[input] : answerValues;

  /// 自增主键；同一局内 id 越大表示点得越晚。
  final int id;

  /// 所属单词主键。
  final int wordId;

  ///
  /// 所属含义主键；可空。
  ///
  /// 听音辨义的「选拼写」这一步针对整个单词而不是某条释义，所以为空。
  final int? meaningId;

  ///
  /// 用户实际选的那个候选词，或者拼错的完整单词。
  ///
  /// 答对时也照样记下来，这样「这一局到底怎么走过来的」可以完整复盘。
  final String input;

  /// 这一次点对了没有。
  final bool isCorrect;

  ///
  /// 从原生记录数据创建模型。
  factory SessionRecord.fromMap(Map<Object?, Object?> map) {
    // 主键缺失时无法唯一识别记录，拒绝构造不完整模型。
    final rawId = map['id'];
    if (rawId is! num) throw const FormatException('会话记录缺少有效 id');
    // 单词外键缺失时无法回查单词详情，必须暴露数据格式错误。
    final rawWordId = map['word_id'];
    if (rawWordId is! num) throw const FormatException('会话记录缺少有效 word_id');

    return SessionRecord(
      id: rawId.toInt(),
      wordId: rawWordId.toInt(),
      meaningId: map['meaning_id'] is num
          ? (map['meaning_id']! as num).toInt()
          : null,
      input: map['input']?.toString() ?? '',
      answerValues: <String>[
        for (final value in map['answers'] as List? ?? const [])
          value.toString(),
      ],
      questionId: (map['question_id'] as num?)?.toInt(),
      groupId: (map['group_id'] as num?)?.toInt(),
      attemptNo: (map['attempt_no'] as num?)?.toInt() ?? 1,
      targetWordIds: <int>[
        for (final id in map['target_word_ids'] as List? ?? const [])
          (id as num).toInt(),
      ],
      targetMeaningIds: <int>[
        for (final id in map['target_meaning_ids'] as List? ?? const [])
          (id as num).toInt(),
      ],
      // 原生用 0/1，测试也允许直接返回 bool。
      isCorrect:
          map['result'] == true ||
          (map['result'] is num && (map['result']! as num).toInt() == 1),
    );
  }
}

///
/// 一局里某个单词的「现场」，由这一局的全部记录归纳而来。
///
/// 页面拿到它就能回答两个问题：这个词答完了吗？当前这条点错过哪些候选？
class WordProgress {
  ///
  /// 创建一个单词在本局的现场快照。
  const WordProgress({
    required this.answeredMeaningIds,
    required this.spellingDone,
    required this.wrongInputsByMeaning,
    required this.spellingWrongInputs,
    required this.hasAnyWrong,
    this.wrongCount = 0,
  });

  ///
  /// 已经答对过的含义主键集合。
  final Set<int> answeredMeaningIds;

  ///
  /// 「选拼写」那一步过了没有（只有听音辨义用得上）。
  final bool spellingDone;

  ///
  /// 每条含义下已经点错过的候选文本；用来把它们置灰。
  final Map<int, Set<String>> wrongInputsByMeaning;

  ///
  /// 「选拼写」那一步已经点错过的候选文本。
  final Set<String> spellingWrongInputs;

  ///
  /// 这一局这个词有没有错过；结算难度时用它判定。
  final bool hasAnyWrong;

  ///
  /// 这一局这个词一共点错过几次。
  ///
  /// 生活化解释：白卡底部那句「本题已答错 N 次」数的是**整个单词**（拼写那步
  /// 加所有释义）累计点错几回，不是只数当前这一小问。[wrongInputsByMeaning] 与
  /// [spellingWrongInputs] 只能说明「哪几个候选该置灰」，它们的长度只在当前
  /// 小问内才有意义，所以单独留这一个总数，页面重进后照样能把 N 显示回来。
  final int wrongCount;

  ///
  /// 今天这个词还没被碰过时使用的空现场。
  static const WordProgress empty = WordProgress(
    answeredMeaningIds: <int>{},
    spellingDone: false,
    wrongInputsByMeaning: <int, Set<String>>{},
    spellingWrongInputs: <String>{},
    hasAnyWrong: false,
    wrongCount: 0,
  );

  ///
  /// 从一局的全部记录里，归纳出指定单词的现场。
  ///
  /// 生活化解释：把这一局的流水账翻一遍，只挑跟这个词有关的行，
  /// 就能还原出「做到哪了、踩过哪些坑」。
  factory WordProgress.fromRecords(List<SessionRecord> records, int wordId) {
    final answered = <int>{};
    final wrongByMeaning = <int, Set<String>>{};
    final spellingWrong = <String>{};
    var spellingDone = false;
    var hasAnyWrong = false;
    var wrongCount = 0;

    for (final record in records) {
      // 只看这个单词的记录，其余跳过。
      if (record.wordId != wordId && !record.targetWordIds.contains(wordId)) {
        continue;
      }
      if (!record.isCorrect) {
        hasAnyWrong = true;
        // 每条答错记录就是一次点错，直接累加就是「本题已答错几次」。
        wrongCount += 1;
      }

      final meaningId = record.meaningId;
      if (meaningId == null) {
        // 含义为空 = 听音辨义的「选拼写」那一步。
        if (record.isCorrect) {
          spellingDone = true;
        } else if (record.input.isNotEmpty) {
          spellingWrong.add(record.input);
        }
        continue;
      }
      if (record.isCorrect) {
        answered.add(meaningId);
        answered.addAll(record.targetMeaningIds);
      } else if (record.input.isNotEmpty) {
        for (final id in <int>{meaningId, ...record.targetMeaningIds}) {
          (wrongByMeaning[id] ??= <String>{}).add(record.input);
        }
      }
    }

    return WordProgress(
      answeredMeaningIds: Set<int>.unmodifiable(answered),
      spellingDone: spellingDone,
      wrongInputsByMeaning: Map<int, Set<String>>.unmodifiable(wrongByMeaning),
      spellingWrongInputs: Set<String>.unmodifiable(spellingWrong),
      hasAnyWrong: hasAnyWrong,
      wrongCount: wrongCount,
    );
  }
}

///
/// 一个单词在本局结算后，原生回传的即时结果。
///
/// 页面拿到它就能立刻显示「难度 +1」或「连对 5 次，难度 -1」，
/// 不用再回头查一次数据库。
class SettleResult {
  ///
  /// 创建一次结算结果。
  const SettleResult({
    required this.isCorrect,
    required this.streak,
    required this.difficultyBefore,
    required this.difficultyAfter,
    required this.reviewedAt,
    this.recentResults = const <bool?>[],
    this.suggestedAdjustment,
    this.adjustment,
    this.manual = false,
    this.usedTimeSeconds = 0,
  });

  /// 当前词的结算明细直接随结果返回，换词不用再取整局所有草稿。
  final int? suggestedAdjustment;
  final int? adjustment;
  final bool manual;
  final int usedTimeSeconds;

  /// 这一轮有没有一次都没错。
  final bool isCorrect;

  ///
  /// 连对次数（含刚刚结算的这一轮）。
  ///
  /// 「一轮」= 这个词在某一局会话里的整体表现：只要那一局里错过一次，
  /// 这一轮就算错。跨模块累计——听音辨义答对、词义连连接着答对，算连续两次。
  final int streak;

  /// 变动前难度。
  final int difficultyBefore;

  /// 变动后难度。
  final int difficultyAfter;

  ///
  /// 本次推进到的复习时间；巩固局不推进，为 null。
  final DateTime? reviewedAt;

  /// 最近几轮的整体结果，最新一轮排在最前。
  final List<bool?> recentResults;

  ///
  /// 难度相对上一次的变化量。
  int get difficultyDelta => difficultyAfter - difficultyBefore;

  ///
  /// 本次有没有真的推进单词的复习时间。
  bool get didAdvanceReview => reviewedAt != null;

  ///
  /// 从原生返回值创建结果。
  factory SettleResult.fromMap(Map<Object?, Object?> map) {
    return SettleResult(
      isCorrect: map['is_correct'] == true,
      streak: _readInt(map['streak']),
      difficultyBefore: _readInt(map['difficulty_before']),
      difficultyAfter: _readInt(map['difficulty_after']),
      reviewedAt: map['reviewed_at'] is num && (map['reviewed_at']! as num) != 0
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['reviewed_at']! as num).toInt(),
            )
          : null,
      recentResults: _readRecentResults(map['recent_results']),
      suggestedAdjustment: (map['suggested_adjustment'] as num?)?.toInt(),
      adjustment: (map['adjustment'] as num?)?.toInt(),
      manual: map['operation'] == 2,
      usedTimeSeconds: _readInt(map['used_time']),
    );
  }

  static List<bool?> _readRecentResults(Object? value) {
    if (value is! List) return const <bool?>[];
    return <bool?>[
      for (final item in value.take(5))
        if (item is bool)
          item
        else if (item is num)
          item.toInt() == 1
        else
          null,
    ];
  }

  ///
  /// 读取一个非负整数；缺失或类型错误时返回 0。
  static int _readInt(Object? value) {
    if (value is! num) return 0;
    final result = value.toInt();
    return result < 0 ? 0 : result;
  }
}
