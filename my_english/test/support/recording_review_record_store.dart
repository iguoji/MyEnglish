import 'package:my_english/models/review_record.dart';
import 'package:my_english/models/review_session.dart';
import 'package:my_english/store/review_record.dart';

///
/// 复习记录 Store 的内存测试实现。
///
/// 只把每次写入的参数原样记下来，不做任何难度或连对次数计算——那些规则属于
/// 原生事务，由 Kotlin 侧负责，Widget 测试只需要确认「页面在正确的时机、
/// 用正确的参数写了记录」。
///
class RecordingReviewRecordStore implements ReviewRecordStore {
  ///
  /// 创建一个只记账的复习记录 Store。
  ///
  RecordingReviewRecordStore();

  ///
  /// 按调用顺序记下的每一次写入。
  final List<RecordedReviewWrite> writes = <RecordedReviewWrite>[];

  @override
  Future<ReviewRecordResult> add({
    required int wordId,
    required ReviewModule module,
    required int? sessionId,
    required int wrongCount,
    required int hintCount,
    required bool updateReviewedAt,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    writes.add(
      RecordedReviewWrite(
        wordId: wordId,
        module: module,
        sessionId: sessionId,
        wrongCount: wrongCount,
        hintCount: hintCount,
        updateReviewedAt: updateReviewedAt,
      ),
    );
    // 返回一份形状正确的结果即可；难度真实计算由原生负责。
    return ReviewRecordResult(
      streak: wrongCount == 0 ? 1 : 0,
      isCorrect: wrongCount == 0,
      difficultyBefore: 0,
      difficultyAfter: wrongCount == 0 ? 0 : 1,
      didAdvanceReview: updateReviewedAt,
    );
  }

  @override
  Future<List<ReviewRecord>> getTodayRecords() async => const <ReviewRecord>[];

  @override
  Future<List<int>> getTodayReviewWordIds() async => const <int>[];

  @override
  Future<int> getTodayReviewWordCount() async => 0;

  @override
  Future<Map<String, int>> getDailyReviewCounts({DateTime? since}) async =>
      const <String, int>{};

  @override
  Future<Map<String, int>> getMonthlyReviewCounts({DateTime? since}) async =>
      const <String, int>{};
}

///
/// 一次复习记录写入的参数快照。
///
class RecordedReviewWrite {
  ///
  /// 记下一次写入。
  const RecordedReviewWrite({
    required this.wordId,
    required this.module,
    required this.sessionId,
    required this.wrongCount,
    required this.hintCount,
    required this.updateReviewedAt,
  });

  /// 单词主键。
  final int wordId;

  /// 所属复习模块。
  final ReviewModule module;

  /// 所属会话主键。
  final int? sessionId;

  /// 本次选错次数。
  final int wrongCount;

  /// 本次提示次数。
  final int hintCount;

  /// 是否推进复习时间。
  final bool updateReviewedAt;

  @override
  String toString() =>
      'RecordedReviewWrite(word: $wordId, module: ${module.storageKey}, '
      'session: $sessionId, wrong: $wrongCount, hint: $hintCount, '
      'advance: $updateReviewedAt)';
}
