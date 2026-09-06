// 会话、记录、词库模型与会话 Store 接口。
import 'package:my_english/models/session.dart';
import 'package:my_english/models/session_record.dart';
import 'package:my_english/models/word_set.dart';
import 'package:my_english/store/session.dart';

///
/// 会话 Store 的内存测试实现。
///
/// 同时承担两种职责：
/// - **有状态行为**：词库、会话、记录都住在内存列表里，getLatest*/create*
///   系列查询与原生 SQLite 语义一致，供 ReviewFlow 之类的流程测试使用；
/// - **记账断言**：把页面写入的参数原样记下来（progressWrites 等），供
///   Widget 测试确认「在正确的时机、用正确的参数写了数据」。
///
/// 难度、连对等计算规则属于 Android 原生事务，这里不做，返回形状正确的结果。
///
class MemorySessionStore implements SessionStore {
  ///
  /// 创建内存会话 Store；可预置词库、会话和固定的「今天」。
  MemorySessionStore({
    List<WordSet> initialWordSets = const <WordSet>[],
    List<Session> initialSessions = const <Session>[],
    String? today,
  }) : wordSets = List<WordSet>.of(initialWordSets),
       sessions = List<Session>.of(initialSessions),
       today = today ?? _defaultToday();

  ///
  /// 内存中的全部词库，按创建顺序排列。
  final List<WordSet> wordSets;

  ///
  /// 内存中的全部会话，按创建顺序排列。
  final List<Session> sessions;

  ///
  /// 测试固定的「今天」，格式 yyyy-MM-dd。
  final String today;

  ///
  /// 下一条词库 / 会话 / 记录的自增主键。
  int _nextWordSetId = 1;
  int _nextSessionId = 1;
  int _nextRecordId = 1;

  ///
  /// 每个会话的点击记录：sessionId → 记录列表。
  final Map<int, List<SessionRecord>> recordsBySession =
      <int, List<SessionRecord>>{};

  // ---- 记账字段（Widget 测试断言用） ------------------------------------

  ///
  /// 按调用顺序记下的「保存进度」调用。
  final List<({int sessionId, int cursor, int elapsed})> progressWrites =
      <({int sessionId, int cursor, int elapsed})>[];

  ///
  /// 按调用顺序记下的「记一次点击」调用。
  final List<RecordedSessionWrite> recordWrites = <RecordedSessionWrite>[];

  ///
  /// 按调用顺序记下的「结算单词」调用。
  final List<({int sessionId, int wordId, bool updateReviewedAt})> settles =
      <({int sessionId, int wordId, bool updateReviewedAt})>[];

  ///
  /// 按调用顺序记下的「收尾」调用。
  final List<({int sessionId, SessionStatus status, int? cursor, int? elapsed})>
  finishes =
      <({int sessionId, SessionStatus status, int? cursor, int? elapsed})>[];

  // ---- 复习词库 ---------------------------------------------------------

  @override
  Future<WordSet?> getLatestWordSet(String date) async => _latestWordSet(date);

  WordSet? _latestWordSet(String date) {
    for (final wordSet in wordSets.reversed) {
      if (wordSet.date == date) return wordSet;
    }
    return null;
  }

  @override
  Future<int> createWordSet({
    required int wordCount,
    required List<int> todayWordIds,
    required List<int> tomorrowWordIds,
    required String date,
  }) async {
    final wordSet = WordSet(
      id: _nextWordSetId++,
      wordCount: wordCount,
      todayWordIds: List<int>.unmodifiable(todayWordIds),
      tomorrowWordIds: List<int>.unmodifiable(tomorrowWordIds),
      date: date,
      createdAt: DateTime.now(),
    );
    wordSets.add(wordSet);
    return wordSet.id;
  }

  // ---- 会话 -------------------------------------------------------------

  @override
  Future<Session?> getLatestSession(ReviewModule module, String date) async =>
      _latestSession(module, date);

  Session? _latestSession(ReviewModule module, String date) {
    for (final session in sessions.reversed) {
      if (session.module == module && session.date == date) return session;
    }
    return null;
  }

  @override
  Future<Session?> getCompletedDailySession(
    ReviewModule module,
    String date,
  ) async {
    for (final session in sessions.reversed) {
      if (session.module == module &&
          session.date == date &&
          session.kind == SessionKind.daily &&
          session.status == SessionStatus.completed) {
        return session;
      }
    }
    return null;
  }

  @override
  Future<Map<ReviewModule, ReviewModuleState>> getTodayModuleStates(
    String date,
  ) async {
    final states = <ReviewModule, ReviewModuleState>{};
    for (final module in ReviewModule.reviewCards) {
      final latest = _latestSession(module, date);
      if (latest == null) continue;
      final dailyCompleted = sessions.any(
        (session) =>
            session.module == module &&
            session.date == date &&
            session.kind == SessionKind.daily &&
            session.status == SessionStatus.completed,
      );
      if (dailyCompleted) {
        final reinforcing =
            latest.kind == SessionKind.reinforce &&
            latest.status == SessionStatus.active;
        states[module] = ReviewModuleState(
          progress: ReviewModuleProgress.completed,
          isReinforcing: reinforcing,
          doneCount: latest.cursor,
          totalCount: latest.total,
          barPhase: reinforcing
              ? ReviewBarPhase.reinforceActive
              : latest.kind == SessionKind.reinforce &&
                    latest.status == SessionStatus.completed
              ? ReviewBarPhase.reinforceDone
              : ReviewBarPhase.dailyDone,
        );
      } else if (latest.kind == SessionKind.daily &&
          latest.status == SessionStatus.active) {
        states[module] = ReviewModuleState(
          progress: ReviewModuleProgress.active,
          doneCount: latest.cursor,
          totalCount: latest.total,
          barPhase: ReviewBarPhase.dailyActive,
        );
      } else {
        states[module] = ReviewModuleState.empty;
      }
    }
    return states;
  }

  @override
  Future<int> createSession({
    required ReviewModule module,
    required SessionKind kind,
    required int? wordSetId,
    required List<Object?> items,
    required String date,
  }) async {
    final session = Session(
      id: _nextSessionId++,
      module: module,
      kind: kind,
      status: SessionStatus.active,
      wordSetId: wordSetId,
      items: List<Object?>.unmodifiable(items),
      cursor: 0,
      elapsed: 0,
      date: date,
      createdAt: DateTime.now(),
    );
    sessions.add(session);
    return session.id;
  }

  @override
  Future<void> updateProgress({
    required int sessionId,
    required int cursor,
    required int elapsed,
  }) async {
    progressWrites.add((
      sessionId: sessionId,
      cursor: cursor,
      elapsed: elapsed,
    ));
    _replaceSession(
      sessionId,
      (session) => _rebuild(session, cursor: cursor, elapsed: elapsed),
    );
  }

  @override
  Future<void> finishSession({
    required int sessionId,
    required SessionStatus status,
    int? cursor,
    int? elapsed,
  }) async {
    finishes.add((
      sessionId: sessionId,
      status: status,
      cursor: cursor,
      elapsed: elapsed,
    ));
    _replaceSession(
      sessionId,
      (session) => _rebuild(
        session,
        status: status,
        cursor: cursor ?? session.cursor,
        elapsed: elapsed ?? session.elapsed,
      ),
    );
  }

  @override
  Future<int> abortStaleSessions(String today) async {
    var count = 0;
    for (var index = sessions.length - 1; index >= 0; index -= 1) {
      final session = sessions[index];
      // 只收掉「不是今天」的进行中会话，今天的进度完整保留。
      if (session.status == SessionStatus.active && session.date != today) {
        sessions[index] = _rebuild(session, status: SessionStatus.aborted);
        count += 1;
      }
    }
    return count;
  }

  @override
  Future<int> abortActiveSessions() async {
    var count = 0;
    for (var index = sessions.length - 1; index >= 0; index -= 1) {
      final session = sessions[index];
      if (session.status == SessionStatus.active) {
        sessions[index] = _rebuild(session, status: SessionStatus.aborted);
        count += 1;
      }
    }
    return count;
  }

  ///
  /// 用 [transform] 生成的副本替换指定会话。
  void _replaceSession(int sessionId, Session Function(Session) transform) {
    final index = sessions.indexWhere((session) => session.id == sessionId);
    if (index < 0) return;
    sessions[index] = transform(sessions[index]);
  }

  ///
  /// 按会话模型不可变约束重建一份副本；Session 本身没有 copyWith，
  /// 这里只替换显式传入的字段，其余原样保留。
  Session _rebuild(
    Session session, {
    SessionStatus? status,
    int? cursor,
    int? elapsed,
  }) => Session(
    id: session.id,
    module: session.module,
    kind: session.kind,
    status: status ?? session.status,
    wordSetId: session.wordSetId,
    items: session.items,
    cursor: cursor ?? session.cursor,
    elapsed: elapsed ?? session.elapsed,
    date: session.date,
    createdAt: session.createdAt,
    updatedAt: session.updatedAt,
  );

  // ---- 会话记录 ---------------------------------------------------------

  @override
  Future<void> addRecord({
    required int sessionId,
    required int wordId,
    int? meaningId,
    required String input,
    required bool isCorrect,
  }) async {
    recordWrites.add(
      RecordedSessionWrite(
        sessionId: sessionId,
        wordId: wordId,
        meaningId: meaningId,
        input: input,
        isCorrect: isCorrect,
      ),
    );
    (recordsBySession[sessionId] ??= <SessionRecord>[]).add(
      SessionRecord(
        id: _nextRecordId++,
        wordId: wordId,
        meaningId: meaningId,
        input: input,
        isCorrect: isCorrect,
      ),
    );
  }

  @override
  Future<List<SessionRecord>> getSessionRecords(int sessionId) async =>
      List<SessionRecord>.unmodifiable(
        recordsBySession[sessionId] ?? const <SessionRecord>[],
      );

  @override
  Future<SettleResult> settleWord({
    required int sessionId,
    required int wordId,
    required bool updateReviewedAt,
  }) async {
    settles.add((
      sessionId: sessionId,
      wordId: wordId,
      updateReviewedAt: updateReviewedAt,
    ));
    // 返回一份形状正确的结果即可；真实难度计算由原生负责。
    return SettleResult(
      isCorrect: true,
      streak: 1,
      difficultyBefore: 0,
      difficultyAfter: 0,
      reviewedAt: updateReviewedAt
          ? DateTime.fromMillisecondsSinceEpoch(1)
          : null,
    );
  }

  // ---- 统计（流程测试用不到，返回安全默认值） ---------------------------

  @override
  Future<int> getTodayCorrectWordCount(String date) async => 0;

  @override
  Future<List<int>> getTodayCorrectWordIds(String date) async => const <int>[];

  @override
  Future<Map<String, int>> getDailyCounts({
    String? since,
    bool correctOnly = false,
  }) async => <String, int>{};

  @override
  Future<Map<String, int>> getMonthlyCounts({String? since}) async =>
      <String, int>{};

  ///
  /// 取当前设备日期的 yyyy-MM-dd 文本。
  static String _defaultToday() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }
}

///
/// 一次「记点击」调用的参数快照。
///
/// 与 [SessionRecord] 分开，是为了记录「调用当时」的原始参数，避免受后续
/// 内存记录追加的影响。
///
class RecordedSessionWrite {
  ///
  /// 创建一次点击调用的参数快照。
  const RecordedSessionWrite({
    required this.sessionId,
    required this.wordId,
    required this.meaningId,
    required this.input,
    required this.isCorrect,
  });

  /// 所属会话主键。
  final int sessionId;

  /// 被点的单词主键。
  final int wordId;

  /// 当前轮的代表含义主键（听音辨义「选拼写」那步可能为空）。
  final int? meaningId;

  /// 用户实际点的候选词文本。
  final String input;

  /// 这一次点对了没有。
  final bool isCorrect;
}
