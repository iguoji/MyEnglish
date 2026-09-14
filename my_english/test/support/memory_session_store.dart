import 'dart:math';

import 'package:my_english/models/word.dart';
import 'package:my_english/models/session_question.dart';
// 会话、记录、词库模型与会话 Store 接口。
import 'package:my_english/models/session.dart';
import 'package:my_english/models/session_record.dart';
import 'package:my_english/models/settlement.dart';
import 'package:my_english/models/word_set.dart';
import 'package:my_english/store/session.dart';
// 计划补缺要按两层规则选词，这里复用词表 Store 的 pickWords。
import 'package:my_english/store/word.dart';

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
    Map<String, int> initialDailyCounts = const <String, int>{},
    Map<String, int> initialDailyDurations = const <String, int>{},
    String? today,
  }) : wordSets = List<WordSet>.of(initialWordSets),
       sessions = List<Session>.of(initialSessions),
       dailyCounts = Map<String, int>.of(initialDailyCounts),
       dailyDurations = Map<String, int>.of(initialDailyDurations),
       today = today ?? _defaultToday();

  ///
  /// 预置的每日复习量（日期 → 当天练过的去重单词数）。
  ///
  /// 首页的打卡月历与趋势曲线读的就是这份聚合，它们原来各自写死
  /// `LocalSessionStore.instance`，测试里只能截获原生通道。现在两处都接受注入，
  /// 用例直接给数据就行，不必再搭一套通道桩。
  final Map<String, int> dailyCounts;

  ///
  /// 预置的每日复习时长（日期 → 当天累计秒数），供趋势曲线使用。
  final Map<String, int> dailyDurations;

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
  /// 计划补缺时用来选词的词表 Store。
  ///
  /// 原生把「读计划 → 算配额 → 补缺选词」放在同一个 SQLite 事务里，所以这一步
  /// 在 Dart 侧没有独立的 Store 方法。内存实现把它拆成「会话库持有计划、
  /// 词表负责选词」两半，需要用例把同一份词表挂进来（`_flow` 已经代劳）。
  /// 不挂也能用，只是计划里缺词时会明确报错，而不是悄悄返回一份空计划。
  WordStore? wordStore;

  ///
  /// 下一条词库 / 会话 / 记录的自增主键。
  int _nextWordSetId = 1;
  int _nextSessionId = 1;
  int _nextRecordId = 1;

  ///
  /// 每个会话的点击记录：sessionId → 记录列表。
  final Map<int, List<SessionRecord>> recordsBySession =
      <int, List<SessionRecord>>{};

  /// 每局尚未正式应用的结算草稿。
  final Map<int, List<SettlementDraft>> settlementDraftsBySession =
      <int, List<SettlementDraft>>{};

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

  // 新接口的内存读写适配。计划（plans + plan_words）按原生语义复刻，
  // 选词那一步委托给挂进来的词表 Store。
  final Map<int, int> _retryCounts = {};
  final Map<int, List<String>> _questionDistractors = {};
  final Map<int, Map<String, Object?>> _playbacks = {};
  int _nextGroupId = 1;
  int _nextQuestionId = 1;

  // ---- 计划（plans / plan_words 的内存版） ------------------------------

  /// 日期 → 计划主键；同一天只对应一份计划。
  final Map<String, int> _planIds = <String, int>{};

  /// 日期 → 计划成员，顺序即写入顺序（先难词、后久词）。
  final Map<String, List<_PlanMember>> _planMembers = <String, List<_PlanMember>>{};

  int _nextPlanId = 1;

  @override
  Future<WordSet?> resolvePlan({
    required String date,
    required int dailyGoal,
    List<int> exclude = const <int>[],
    bool ensureTomorrow = true,
  }) async {
    final plan = await _resolvePlan(date, dailyGoal, ensureTomorrow, exclude);
    if (plan == null) return null;
    // wordSets 是「调用方明确要过哪一天」的公开视图：按日期覆盖，反复调用同一天
    // 不会重复追加。明日计划是内部维护的，不进这个列表——它只是今天的预建，
    // 用例关心的「今天这份计划只建了一次」不该被它干扰。
    final index = wordSets.indexWhere((set) => set.date == date);
    if (index < 0) {
      wordSets.add(plan);
    } else {
      wordSets[index] = plan;
    }
    return plan;
  }

  ///
  /// 原生 `resolvePlan` 的内存版：读计划 → 按 40/60 配额削减 → 补缺选词 →
  /// 顺手预建明天 → 回读计划视图。
  ///
  /// 每一步都对着 `StudyRepository.resolvePlan` 写，差异只在于这里没有软删时间戳，
  /// 用一个 `deleted` 标记代替。
  ///
  Future<WordSet?> _resolvePlan(
    String date,
    int target,
    bool ensureTomorrow,
    List<int> exclude,
  ) async {
    final existing = _planIds[date];
    // 没有计划、目标又是 0：没有任何可建的内容。
    if (existing == null && target <= 0) return null;
    // 第一次见到这一天就登记一份计划；编号本身后面不再用到，
    // 这一步只是为了把「日期 → 计划主键」这条映射建起来。
    if (existing == null) _planIds[date] = _nextPlanId++;
    final members = _planMembers.putIfAbsent(date, () => <_PlanMember>[]);

    // 还能留用的成员：单词没被删、也不在本次排除名单里。
    final live = await _liveWordIds();
    final alive = <_PlanMember>[
      for (final member in members)
        if (!member.deleted &&
            !exclude.contains(member.wordId) &&
            live.contains(member.wordId))
          member,
    ];
    final hardAlive = <_PlanMember>[
      for (final member in alive)
        if (member.type == PlanLayer.hard) member,
    ];
    final staleAlive = <_PlanMember>[
      for (final member in alive)
        if (member.type == PlanLayer.stale) member,
    ];
    // 目标变小时按 40/60 的分层配额各留一部分：计划成员是按「先难词、后久词」
    // 的顺序写进去的，若直接从头截断，砍掉的全是排在后面的久词。
    final hardQuota = min(
      hardAlive.length,
      min((target * 0.4).ceil(), target),
    );
    final staleQuota = min(staleAlive.length, target - hardQuota);
    final kept = <_PlanMember>[
      ...hardAlive.take(hardQuota),
      ...staleAlive.take(staleQuota),
    ];
    // 某一层不足时用另一层的剩余成员补满，削减后不会凭空空出几个位置。
    for (final member in <_PlanMember>[
      ...hardAlive.skip(hardQuota),
      ...staleAlive.skip(staleQuota),
    ]) {
      if (kept.length >= target) break;
      kept.add(member);
    }
    final keptIds = <int>{for (final member in kept) member.wordId};
    for (final member in members) {
      if (!member.deleted && !keptIds.contains(member.wordId)) {
        member.deleted = true;
      }
    }

    final missing = target - kept.length;
    if (missing > 0) {
      final blocked = <int>[...exclude, ...keptIds];
      final hard = await _pickWords(
        limit: (missing * 0.4).ceil(),
        exclude: blocked,
        layer: PickLayer.hard,
      );
      final stale = await _pickWords(
        limit: missing - hard.length,
        exclude: <int>[...blocked, ...hard],
        layer: PickLayer.stale,
      );
      for (final id in hard) {
        members.add(_PlanMember(id, PlanLayer.hard));
      }
      for (final id in stale) {
        members.add(_PlanMember(id, PlanLayer.stale));
      }
    }

    // 只向前准备一天，避免递归生成无穷日期。
    if (ensureTomorrow && target > 0) {
      final todayIds = <int>[
        for (final member in members)
          if (!member.deleted) member.wordId,
      ];
      await _resolvePlan(_nextDate(date), target, false, todayIds);
    }
    return _readPlan(date);
  }

  ///
  /// 把 [date] 这份计划读成视图；今天与明天的成员分别来自各自的计划。
  ///
  WordSet? _readPlan(String date) {
    final planId = _planIds[date];
    if (planId == null) return null;
    final members = <_PlanMember>[
      for (final member in _planMembers[date] ?? const <_PlanMember>[])
        if (!member.deleted) member,
    ];
    final tomorrow = _nextDate(date);
    final tomorrowMembers = _planMembers[tomorrow] ?? const <_PlanMember>[];
    return WordSet(
      id: planId,
      wordCount: members.length,
      todayWordIds: List<int>.unmodifiable(<int>[
        for (final member in members) member.wordId,
      ]),
      tomorrowWordIds: List<int>.unmodifiable(<int>[
        for (final member in tomorrowMembers)
          if (!member.deleted) member.wordId,
      ]),
      date: date,
      createdAt: DateTime.now(),
      hardWordIds: List<int>.unmodifiable(<int>[
        for (final member in members)
          if (member.type == PlanLayer.hard) member.wordId,
      ]),
    );
  }

  ///
  /// 当前词表里还存在的单词主键；没有挂词表时视为「都在」。
  ///
  Future<Set<int>> _liveWordIds() async {
    final store = wordStore;
    if (store == null) return const <int>{};
    final words = await store.getAll();
    return <int>{
      for (final word in words)
        if (word.id != null) word.id!,
    };
  }

  ///
  /// 按分层规则向词表要一批词；没挂词表就明确报错。
  ///
  Future<List<int>> _pickWords({
    required int limit,
    required List<int> exclude,
    required PickLayer layer,
  }) {
    final store = wordStore;
    if (store == null) {
      throw StateError(
        '内存会话库没有挂词表 Store，无法为计划补缺选词；'
        '请先给 MemorySessionStore.wordStore 赋值。',
      );
    }
    return store.pickWords(limit: limit, exclude: exclude, layer: layer);
  }

  ///
  /// 把 yyyy-MM-dd 往后推一天。
  ///
  String _nextDate(String date) {
    final parts = date.split('-');
    final next = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    ).add(const Duration(days: 1));
    return '${next.year.toString().padLeft(4, '0')}-'
        '${next.month.toString().padLeft(2, '0')}-'
        '${next.day.toString().padLeft(2, '0')}';
  }

  @override
  Future<Session?> getSession(int id) async {
    for (final session in sessions) {
      if (session.id == id) return _rebuild(session);
    }
    return null;
  }

  @override
  Future<Session?> getActiveSession(
    ReviewModule module,
    String date, {
    bool selfTest = false,
    bool headerOnly = false,
  }) async {
    for (final session in sessions.reversed) {
      if (session.module == module &&
          session.date == date &&
          session.isActive &&
          (session.kind == SessionKind.selfTest) == selfTest) {
        return _rebuild(session);
      }
    }
    return null;
  }

  @override
  Future<Session?> getLatestSelfSession(
    ReviewModule module,
    String date,
  ) async {
    for (final session in sessions.reversed) {
      if (session.module == module &&
          session.date == date &&
          session.kind == SessionKind.selfTest) {
        return _rebuild(session);
      }
    }
    return null;
  }

  @override
  Future<Session> createStudySession({
    required ReviewModule module,
    required SessionKind kind,
    required int? planId,
    required List<Word> words,
    required List<Map<String, Object?>> groups,
    required String date,
  }) async {
    if (kind == SessionKind.selfTest) {
      for (var i = 0; i < sessions.length; i++) {
        final previous = sessions[i];
        if (previous.module == module &&
            previous.date == date &&
            previous.kind == kind &&
            previous.isActive) {
          sessions[i] = _rebuild(previous, status: SessionStatus.aborted);
        }
      }
    }
    final paper = <Map<String, Object?>>[];
    for (var index = 0; index < groups.length; index++) {
      final groupId = _nextGroupId++;
      final questions = <Map<String, Object?>>[];
      final source = groups[index]['questions']! as List;
      for (var q = 0; q < source.length; q++) {
        questions.add({
          ...Map<String, Object?>.from(source[q] as Map),
          'id': _nextQuestionId++,
          'main_question_id': groupId,
          'question_no': q + 1,
        });
      }
      paper.add({
        'id': groupId,
        'question_no': index + 1,
        'phase': index == 0 ? 1 : 0,
        'current_sub_question_id': questions.first['id'],
        'questions': questions,
      });
    }
    final flat = <Map<String, Object?>>[
      for (final group in paper)
        ...group['questions']! as List<Map<String, Object?>>,
    ];
    int wordId(Map<String, Object?> q) =>
        ((q['details']! as List).first as Map)['word_id'] as int;
    final items = switch (module) {
      ReviewModule.listeningMeaning => <Object?>[
        for (final group in paper)
          wordId((group['questions']! as List<Map<String, Object?>>).first),
      ],
      ReviewModule.meaningMatch => <Object?>[
        for (final group in paper)
          <Object?>[
            for (final q in group['questions']! as List<Map<String, Object?>>)
              <Object?>[
                wordId(q),
                ((q['details']! as List).first as Map)['meaning_id'],
              ],
          ],
      ],
      ReviewModule.meaningWordChoice => <Object?>[
        for (final q in flat) q['id'],
      ],
      _ => <Object?>[for (final q in flat) wordId(q)],
    };
    final session = Session.fromMap({
      'id': _nextSessionId++,
      'module': module.storageKey,
      'kind': kind.code,
      'status': SessionStatus.active.code,
      'word_set_id': planId,
      'date': date,
      'items': items,
      'groups': paper,
      'words': words.map((word) => word.toMap()).toList(),
    });
    sessions.add(session);
    return session;
  }

  List<SessionRecord> _currentRecords(int id) => <SessionRecord>[
    for (final record in recordsBySession[id] ?? const <SessionRecord>[])
      if (record.attemptNo == (_retryCounts[record.groupId] ?? 0) + 1) record,
  ];

  @override
  Future<SessionRecord> submitAnswer({
    required int sessionId,
    required int questionId,
    required List<String> answers,
    int elapsed = 0,
    int usedSeconds = 0,
  }) async {
    final session = (await getSession(sessionId))!;
    final q = session.questions.firstWhere(
      (question) => question.id == questionId,
    );
    final correct = q.type == 400
        ? session.questions.any(
            (right) =>
                right.mainQuestionId == q.mainQuestionId &&
                right.content.first == q.content.first &&
                right.answers.contains(answers.single),
          )
        : q.answers.any(
            (answer) => q.answerType == 1
                ? answer.toLowerCase() == answers.single.toLowerCase()
                : answer == answers.single,
          );
    final record = SessionRecord(
      id: _nextRecordId++,
      wordId: q.details.first.wordId,
      meaningId: q.details.first.meaningId,
      input: answers.single,
      isCorrect: correct,
      questionId: q.id,
      groupId: q.mainQuestionId,
      attemptNo: (_retryCounts[q.mainQuestionId] ?? 0) + 1,
      targetWordIds: q.wordIds.toList(),
      targetMeaningIds: <int>[
        for (final d in q.details)
          if (d.meaningId != null) d.meaningId!,
      ],
    );
    (recordsBySession[sessionId] ??= []).add(record);
    recordWrites.add(
      RecordedSessionWrite(
        sessionId: sessionId,
        wordId: record.wordId,
        meaningId: record.meaningId,
        input: record.input,
        isCorrect: correct,
      ),
    );
    return record;
  }

  @override
  Future<Session> retryGroup(int sessionId, int groupId) async {
    _retryCounts[groupId] = (_retryCounts[groupId] ?? 0) + 1;
    return (await getSession(sessionId))!;
  }

  @override
  Future<void> saveQuestionDistractors({
    required int sessionId,
    required int questionId,
    required List<String> distractors,
    required List<Map<String, Object?>> sources,
  }) async {
    _questionDistractors[questionId] = distractors;
  }

  @override
  Future<void> savePlayback({
    required int sessionId,
    required int cursor,
    required int elapsed,
    required Map<String, Object?> playback,
  }) async {
    _playbacks[sessionId] = playback;
    await updateProgress(
      sessionId: sessionId,
      cursor: cursor,
      elapsed: elapsed,
    );
  }

  // ---- 复习词库 ---------------------------------------------------------

  @override
  Future<WordSet?> getLatestWordSet(String date) async => _latestWordSet(date);

  WordSet? _latestWordSet(String date) {
    for (final wordSet in wordSets.reversed) {
      if (wordSet.date == date) return wordSet;
    }
    return null;
  }

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

  ///
  /// 预置一条会话，并让自增主键跳过它。
  ///
  /// 页面测试常常先用 [buildSession] 拼好一局，再把页面指向它；这局会话必须
  /// 同时出现在这里，`submitAnswer` / `updateProgress` / `prepareSettlement`
  /// 这些按编号回查会话的方法才找得到它。
  ///
  void seedSession(Session session) {
    sessions.add(session);
    if (session.id >= _nextSessionId) _nextSessionId = session.id + 1;
  }

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
    Map<int, int> questionTimes = const <int, int>{},
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
    bool pendingSettlement = false,
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
  Future<int> recoverPendingSettlements() async => 0;

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
    groups: <SessionMainQuestion>[
      for (final group in session.groups)
        SessionMainQuestion(
          id: group.id,
          no: group.no,
          phase: group.phase,
          retryCount: _retryCounts[group.id] ?? group.retryCount,
          currentSubQuestionId: group.currentSubQuestionId,
          questions: <SessionSubQuestion>[
            for (final q in group.questions)
              SessionSubQuestion(
                id: q.id,
                mainQuestionId: q.mainQuestionId,
                no: q.no,
                type: q.type,
                contentType: q.contentType,
                answerType: q.answerType,
                content: q.content,
                answers: q.answers,
                details: q.details,
                distractors: _questionDistractors[q.id] ?? q.distractors,
                usedSeconds: q.usedSeconds,
              ),
          ],
        ),
    ],
    snapshotWords: session.snapshotWords,
    records: _currentRecords(session.id),
    playback: _playbacks[session.id] ?? session.playback,
    settlementStatus: session.settlementStatus,
    answerSeconds: session.answerSeconds,
  );

  // ---- 会话记录 ---------------------------------------------------------

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
      _currentRecords(sessionId);

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

  @override
  Future<SettleResult> prepareSettlement({
    required int sessionId,
    required int wordId,
  }) async {
    // 测试里的会话常常是当场拼出来的，不一定在 Store 的会话表里；
    // 找不着就按「主线」处理，不能因为查不到就让结算直接崩掉。
    var updatesReviewedAt = true;
    for (final session in sessions) {
      if (session.id == sessionId) {
        updatesReviewedAt = session.updatesReviewedAt;
        break;
      }
    }
    settles.add((
      sessionId: sessionId,
      wordId: wordId,
      updateReviewedAt: updatesReviewedAt,
    ));
    final records = recordsBySession[sessionId] ?? const <SessionRecord>[];
    final wordRecords = records.where((record) => record.wordId == wordId);
    final isCorrect = wordRecords.every((record) => record.isCorrect);
    await upsertSettlementDraft(
      SettlementDraft(
        sessionId: sessionId,
        wordId: wordId,
        isCorrect: isCorrect,
        streak: isCorrect ? 1 : 0,
        difficultyBefore: 0,
        suggestedAdjustment: isCorrect ? 0 : 1,
        adjustment: isCorrect ? 0 : 1,
        manual: false,
        usedTimeSeconds: 0,
      ),
    );
    return SettleResult(
      isCorrect: isCorrect,
      streak: isCorrect ? 1 : 0,
      difficultyBefore: 0,
      difficultyAfter: isCorrect ? 0 : 1,
      reviewedAt: null,
    );
  }

  Future<void> upsertSettlementDraft(SettlementDraft draft) async {
    final drafts = settlementDraftsBySession[draft.sessionId] ??=
        <SettlementDraft>[];
    final index = drafts.indexWhere((item) => item.wordId == draft.wordId);
    if (index < 0) {
      drafts.add(draft);
    } else {
      drafts[index] = draft;
    }
  }

  @override
  Future<void> updateSettlementDraft({
    required int sessionId,
    required int wordId,
    required int difficultyAfter,
    required int adjustment,
    required int operation,
  }) async {
    final drafts = settlementDraftsBySession[sessionId];
    if (drafts == null) return;
    final index = drafts.indexWhere((item) => item.wordId == wordId);
    if (index < 0) return;
    final current = drafts[index];
    final nextAdjust = difficultyAdjustFromDelta(adjustment);
    drafts[index] = current.copyWithAdjust(nextAdjust);
  }

  @override
  Future<List<SettlementDraft>> getSettlementDrafts(int sessionId) async =>
      List<SettlementDraft>.unmodifiable(
        settlementDraftsBySession[sessionId] ?? const <SettlementDraft>[],
      );

  @override
  Future<void> finalizeSessionSettlement(int sessionId) async {
    settlementDraftsBySession.remove(sessionId);
  }

  // ---- 统计（流程测试用不到，返回安全默认值） ---------------------------

  @override
  Future<int> getTodayReviewedWordCount(String date) async => 0;

  @override
  Future<List<int>> getTodayReviewedWordIds(String date) async => const <int>[];

  @override
  Future<Map<String, int>> getDailyCounts({
    String? since,
    bool correctOnly = false,
  }) async => _sinceFiltered(dailyCounts, since);

  @override
  Future<Map<String, int>> getDailyDurations({String? since}) async =>
      _sinceFiltered(dailyDurations, since);

  /// 原生只返回 `since` 当天及之后的行；内存版照做，免得用例误以为全量返回。
  Map<String, int> _sinceFiltered(Map<String, int> source, String? since) {
    if (since == null) return Map<String, int>.of(source);
    return <String, int>{
      for (final entry in source.entries)
        if (entry.key.compareTo(since) >= 0) entry.key: entry.value,
    };
  }

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
/// 计划成员的分层标记；取值与原生 `WordsDatabase.LAYER_HARD / LAYER_STALE` 对齐。
///
/// 难词层是「又难又重」的词，久词层是「又轻又久」的词，削减计划时两层按 40/60
/// 配额各留一部分，靠的就是这个标记，而不是数组里的位置。
///
abstract final class PlanLayer {
  ///
  /// 难词层。
  static const int hard = 1;

  ///
  /// 久词层。
  static const int stale = 2;
}

///
/// 计划里的一个成员（对应原生 `plan_words` 的一行）。
///
/// 用可变的 [deleted] 代替原生的软删时间戳：内存实现只关心「这一行还算不算数」，
/// 不需要留删除时间。
///
class _PlanMember {
  ///
  /// 记下一个成员。
  _PlanMember(this.wordId, this.type);

  /// 单词主键。
  final int wordId;

  /// 分层标记，见 [PlanLayer]。
  final int type;

  /// 是否已被软删。
  bool deleted = false;
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
