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
  });

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
  /// 今天这个词还没被碰过时使用的空现场。
  static const WordProgress empty = WordProgress(
    answeredMeaningIds: <int>{},
    spellingDone: false,
    wrongInputsByMeaning: <int, Set<String>>{},
    spellingWrongInputs: <String>{},
    hasAnyWrong: false,
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

    for (final record in records) {
      // 只看这个单词的记录，其余跳过。
      if (record.wordId != wordId) continue;
      if (!record.isCorrect) hasAnyWrong = true;

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
      } else if (record.input.isNotEmpty) {
        (wrongByMeaning[meaningId] ??= <String>{}).add(record.input);
      }
    }

    return WordProgress(
      answeredMeaningIds: Set<int>.unmodifiable(answered),
      spellingDone: spellingDone,
      wrongInputsByMeaning: Map<int, Set<String>>.unmodifiable(wrongByMeaning),
      spellingWrongInputs: Set<String>.unmodifiable(spellingWrong),
      hasAnyWrong: hasAnyWrong,
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
  });

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
          ? DateTime.fromMillisecondsSinceEpoch((map['reviewed_at']! as num).toInt())
          : null,
    );
  }

  ///
  /// 读取一个非负整数；缺失或类型错误时返回 0。
  static int _readInt(Object? value) {
    if (value is! num) return 0;
    final result = value.toInt();
    return result < 0 ? 0 : result;
  }
}
