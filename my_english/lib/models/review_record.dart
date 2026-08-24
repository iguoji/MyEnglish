import 'review_session.dart';

///
/// 一次单词复习的记录。
///
/// 四个复习模块每答完一个单词就写一条，全部落在同一张表里，靠 [module] 区分。
///
/// 字段里有两组「前后值」，都是为了以后能把一次复习完整复盘出来：
/// - [difficultyBefore] / [difficultyAfter]：这次答题让难度怎么变的；
/// - [reviewedAtBefore] / [reviewedAtAfter]：这次答题有没有推进复习时间。
///   巩固会话不推进复习时间，两个值会完全相同，一眼就能看出「练了但没算数」。
class ReviewRecord {
  ///
  /// 创建一条复习记录。
  const ReviewRecord({
    required this.id,
    required this.wordId,
    required this.streak,
    required this.module,
    required this.sessionId,
    required this.isCorrect,
    required this.wrongCount,
    required this.hintCount,
    required this.difficultyBefore,
    required this.difficultyAfter,
    required this.reviewedAtBefore,
    required this.reviewedAtAfter,
    required this.createdAt,
    required this.createdDate,
  });

  /// 自增主键。
  final int id;

  /// 所属单词主键。
  final int wordId;

  ///
  /// 连对次数。
  ///
  /// 答对就在这个词上一条记录的基础上 +1，答错直接归 0。跨模块累计——
  /// 听音辨义答对、词义连连接着答对，算连续两次。连对次数每满 5 的倍数
  /// （5、10、15…）就把难度降 1。
  final int streak;

  /// 产生记录的复习模块；历史或未知键无法识别时为 null。
  final ReviewModule? module;

  /// 所属会话主键；词库底部的普通听音辨义不属于任何会话，为 null。
  final int? sessionId;

  /// 本次答题过程中是否一个都没选错。
  final bool isCorrect;

  /// 本次选错次数。
  final int wrongCount;

  /// 本次点击提示次数；只留档，不影响正误判定。
  final int hintCount;

  /// 变动前难度。
  final int difficultyBefore;

  /// 变动后难度。
  final int difficultyAfter;

  /// 变动前的最近复习时间；从未复习过时为 null。
  final DateTime? reviewedAtBefore;

  /// 变动后的最近复习时间；巩固会话下与 [reviewedAtBefore] 完全相同。
  final DateTime? reviewedAtAfter;

  /// 写入时间（毫秒时间戳）。
  final int createdAt;

  /// 本地日期，格式 yyyy-MM-dd。
  final String createdDate;

  ///
  /// 这次答题有没有真的推进单词的复习时间。
  ///
  /// 巩固会话只练手不算数，前后两个时间会完全一样。
  bool get didAdvanceReview => reviewedAtBefore != reviewedAtAfter;

  ///
  /// 从原生记录数据创建模型。
  factory ReviewRecord.fromMap(Map<Object?, Object?> map) {
    // 主键缺失时无法唯一识别记录，拒绝构造不完整模型。
    final rawId = map['id'];
    if (rawId is! num) throw const FormatException('复习记录缺少有效 id');

    // 单词外键缺失时无法回查单词详情，必须暴露数据格式错误。
    final rawWordId = map['word_id'];
    if (rawWordId is! num) throw const FormatException('复习记录缺少有效 word_id');

    return ReviewRecord(
      id: rawId.toInt(),
      wordId: rawWordId.toInt(),
      // 连对次数缺失时按 0 处理，等价于「这条之后要重新数」。
      streak: _readInt(map['streak']),
      // 模块无法识别不影响这条记录本身可读，交给调用方决定是否跳过。
      module: ReviewModule.tryFromStorageKey(map['module']?.toString()),
      sessionId: map['session_id'] is num
          ? (map['session_id']! as num).toInt()
          : null,
      // 原生 SQLite 用 0/1，测试也允许直接返回 bool。
      isCorrect:
          map['is_correct'] == true ||
          (map['is_correct'] is num && (map['is_correct']! as num).toInt() == 1),
      wrongCount: _readInt(map['wrong_count']),
      hintCount: _readInt(map['hint_count']),
      difficultyBefore: _readInt(map['difficulty_before']),
      difficultyAfter: _readInt(map['difficulty_after']),
      reviewedAtBefore: _readTime(map['reviewed_at_before']),
      reviewedAtAfter: _readTime(map['reviewed_at_after']),
      createdAt: _readInt(map['created_at']),
      createdDate: map['created_date']?.toString() ?? '',
    );
  }

  ///
  /// 读取一个非负整数；缺失或类型错误时返回 0。
  static int _readInt(Object? value) {
    if (value is! num) return 0;
    final result = value.toInt();
    return result < 0 ? 0 : result;
  }

  ///
  /// 把原生毫秒时间戳转成 DateTime；缺失或为 0 时返回 null。
  static DateTime? _readTime(Object? value) {
    // 0 在数据库里代表「从未复习过」，不能显示成 1970 年。
    if (value is! num || value.toInt() == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
}

///
/// 写入一条复习记录后原生回传的即时结果。
///
/// 页面拿到它就能立刻显示「难度 +1」或「连对 5 次，难度 -1」，
/// 不用再回头查一次数据库。
class ReviewRecordResult {
  ///
  /// 创建一次写入结果。
  const ReviewRecordResult({
    required this.streak,
    required this.isCorrect,
    required this.difficultyBefore,
    required this.difficultyAfter,
    required this.didAdvanceReview,
  });

  /// 本次写入后的连对次数。
  final int streak;

  /// 本次是否一气呵成。
  final bool isCorrect;

  /// 变动前难度。
  final int difficultyBefore;

  /// 变动后难度。
  final int difficultyAfter;

  /// 本次是否推进了单词的复习时间。
  final bool didAdvanceReview;

  ///
  /// 难度相对上一次的变化量。
  int get difficultyDelta => difficultyAfter - difficultyBefore;

  ///
  /// 从原生返回值创建结果。
  factory ReviewRecordResult.fromMap(Map<Object?, Object?> map) {
    // 时间戳可能相等（巩固会话），比较前后值即可判断有没有推进。
    final before = map['reviewed_at_before'];
    final after = map['reviewed_at_after'];
    return ReviewRecordResult(
      streak: ReviewRecord._readInt(map['streak']),
      isCorrect: map['is_correct'] == true,
      difficultyBefore: ReviewRecord._readInt(map['difficulty_before']),
      difficultyAfter: ReviewRecord._readInt(map['difficulty_after']),
      didAdvanceReview:
          before is num && after is num && before.toInt() != after.toInt(),
    );
  }
}
