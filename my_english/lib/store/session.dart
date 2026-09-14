import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/session.dart';
import '../models/session_record.dart';
import '../models/settlement.dart';
import '../models/word_set.dart';
import '../models/word.dart';
import '../services/study_open_timing.dart';

/// 所有模块共用的数据接口，业务写入由 Android 在同一事务中完成。
abstract interface class SessionStore {
  /// 按最新目标维护当天计划，并准备明日计划；词库暂时不足时保留目标。
  Future<WordSet?> resolvePlan({
    required String date,
    required int dailyGoal,
    List<int> exclude = const <int>[],
    bool ensureTomorrow = true,
  });

  /// 读取整份会话、试卷、词库快照与当前遍次的答题记录。
  Future<Session?> getSession(int id);

  /// 首页练习与自测分别查询；自测还须有已保存答案，刚创建的空局不提供恢复。
  Future<Session?> getActiveSession(
    ReviewModule module,
    String date, {
    bool selfTest = false,
    bool headerOnly = false,
  });

  /// 读取某模块当天最新的自测会话。
  Future<Session?> getLatestSelfSession(ReviewModule module, String date);

  /// 在一次写入中保存会话、试卷和词库副本，返回完整会话。
  Future<Session> createStudySession({
    required ReviewModule module,
    required SessionKind kind,
    required int? planId,
    required List<Word> words,
    required List<Map<String, Object?>> groups,
    required String date,
  });

  /// 按实际小题编号保存文本答案，由本地数据库判对并推进题内进度。
  Future<SessionRecord> submitAnswer({
    required int sessionId,
    required int questionId,
    required List<String> answers,
    int elapsed = 0,
    int usedSeconds = 0,
  });

  /// 听音辨义整词进入新一遍，旧答案保留但不再参与本遍结算。
  Future<Session> retryGroup(int sessionId, int groupId);

  /// 一起保存题目混淆选项、来源混淆字段和会话副本；不保存候选顺序。
  Future<void> saveQuestionDistractors({
    required int sessionId,
    required int questionId,
    required List<String> distractors,
    required List<Map<String, Object?>> sources,
  });

  /// 保存当前播放位置、完成遍数、剩余间隔及暂停状态。
  Future<void> savePlayback({
    required int sessionId,
    required int cursor,
    required int elapsed,
    required Map<String, Object?> playback,
  });

  /// 只读取已经存在的计划视图；需要补缺时使用 resolvePlan。
  Future<WordSet?> getLatestWordSet(String date);

  /// 读取首页某模块当天最新会话，不混入自测。
  Future<Session?> getLatestSession(ReviewModule module, String date);

  /// 判断当天是否已经完成过这个模块的复习。
  Future<Session?> getCompletedDailySession(ReviewModule module, String date);

  /// 从会话及题目游标取得首页模块状态和进度。
  Future<Map<ReviewModule, ReviewModuleState>> getTodayModuleStates(
    String date,
  );

  /// 把页面进度映射到大题、小题游标，并保存前台停留和各题答题用时。
  Future<void> updateProgress({
    required int sessionId,
    required int cursor,
    required int elapsed,
    Map<int, int> questionTimes = const <int, int>{},
  });

  /// 核对所有题目完成后准备整局结算；普通退出不调用本方法。
  Future<void> finishSession({
    required int sessionId,
    required SessionStatus status,
    int? cursor,
    int? elapsed,
    bool pendingSettlement = false,
  });

  /// 核对某词全部题目并保存结算草稿，暂不修改难度。
  Future<SettleResult> prepareSettlement({
    required int sessionId,
    required int wordId,
  });

  /// 保存用户手动选择的难度变化，等待正式落实。
  Future<void> updateSettlementDraft({
    required int sessionId,
    required int wordId,
    required int difficultyAfter,
    required int adjustment,
    required int operation,
  });

  /// 读取本局结算及派生的最近表现、连对次数和实际用时。
  Future<List<SettlementDraft>> getSettlementDrafts(int sessionId);

  /// 一次落实本局结算，重复调用只产生一次难度变化。
  Future<void> finalizeSessionSettlement(int sessionId);

  /// 启动时落实已完成但尚未提交的结算。
  Future<int> recoverPendingSettlements();

  /// 中断跨天后仍未完成的会话，保留历史记录。
  Future<int> abortStaleSessions(String today);

  /// 维护操作中断进行中的会话；修改每日目标不调用它。
  Future<int> abortActiveSessions();

  /// 读取每个大题当前遍次的答案，保留具体小题编号。
  Future<List<SessionRecord>> getSessionRecords(int sessionId);

  /// 从已落实结算按日期和单词去重，答错也算练过。
  Future<int> getTodayReviewedWordCount(String date);

  /// 读取当天已落实结算涉及的不同单词编号。
  Future<List<int>> getTodayReviewedWordIds(String date);

  /// 顶部、曲线和热力图共用的每日已复习词数。
  Future<Map<String, int>> getDailyCounts({String? since, bool correctOnly});

  /// 曲线（复习时间）共用的每日累计复习时长（秒）：会话表 elapsed_seconds 的每日汇总。
  Future<Map<String, int>> getDailyDurations({String? since});

  /// 按月统计已落实结算中的不同单词。
  Future<Map<String, int>> getMonthlyCounts({String? since});
}

///
/// 本地会话 Store：全部读写都通过 MethodChannel 交给 Android 原生 SQLite。
///
class LocalSessionStore implements SessionStore {
  ///
  /// 允许测试注入原生通道；正式 App 使用默认值。
  const LocalSessionStore({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  ///
  /// App 默认复用同一个实例。
  static const LocalSessionStore instance = LocalSessionStore();

  ///
  /// 通道名必须与 Android MainActivity 完全一致；与单词共用同一条通道。
  static const MethodChannel _defaultChannel = MethodChannel(
    'my_english/word_store',
  );

  ///
  /// 读写数据用的原生通道。
  final MethodChannel _channel;

  @override
  Future<WordSet?> resolvePlan({
    required String date,
    required int dailyGoal,
    List<int> exclude = const <int>[],
    bool ensureTomorrow = true,
  }) async {
    final row = await _channel
        .invokeMapMethod<Object?, Object?>('resolvePlan', <String, Object?>{
          'date': date,
          'dailyGoal': dailyGoal,
          'exclude': exclude,
          'ensureTomorrow': ensureTomorrow,
        });
    return row == null ? null : WordSet.fromMap(row);
  }

  Future<Session?> _sessionCall(
    String method,
    Map<String, Object?> payload,
  ) async {
    final timing = method == 'createStudySession'
        ? StudyOpenTiming.current
        : null;
    if (timing != null) payload = {...payload, '_open_trace_id': timing.id};
    if (!identical(_channel.codec, const StandardMethodCodec())) {
      final row = await _channel.invokeMapMethod<Object?, Object?>(
        method,
        _sessionArguments(payload),
      );
      return row == null ? null : Session.fromMap(row);
    }
    final words = payload['words'];
    final input = (method: method, arguments: payload);
    final encoded = words is List && words.length >= 128
        ? await compute(
            _encodeSessionCall,
            input,
            debugLabel: 'encode-study-session',
          )
        : _encodeSessionCall(input);
    timing?.mark('request_encoded');
    timing?.detail('request_bytes', encoded.lengthInBytes);
    final reply = await _channel.binaryMessenger.send(_channel.name, encoded);
    timing?.mark('reply_received');
    if (reply == null) throw MissingPluginException('未找到学习数据接口 $method');
    timing?.detail('reply_bytes', reply.lengthInBytes);
    // 解包几千道题及构造词义分组也放到工作线程，页面过渡不被大回包打断。
    final session = reply.lengthInBytes >= 65536
        ? await compute(
            _decodeSessionReply,
            reply,
            debugLabel: 'decode-study-session',
          )
        : _decodeSessionReply(reply);
    timing?.mark('reply_decoded');
    return session;
  }

  @override
  Future<Session?> getSession(int id) => _sessionCall('getSession', {'id': id});

  @override
  Future<Session?> getActiveSession(
    ReviewModule module,
    String date, {
    bool selfTest = false,
    bool headerOnly = false,
  }) => _sessionCall('getActiveSession', {
    'module': module.storageKey,
    'date': date,
    'selfTest': selfTest,
    'headerOnly': headerOnly,
  });

  @override
  Future<Session?> getLatestSelfSession(ReviewModule module, String date) =>
      _sessionCall('getLatestSession', {
        'module': module.storageKey,
        'date': date,
        'selfTest': true,
      });

  @override
  Future<Session> createStudySession({
    required ReviewModule module,
    required SessionKind kind,
    required int? planId,
    required List<Word> words,
    required List<Map<String, Object?>> groups,
    required String date,
  }) async {
    final session = await _sessionCall('createStudySession', {
      'module': module.storageKey,
      'kind': kind.code,
      'planId': planId,
      'words': words,
      'groups': groups,
      'date': date,
    });
    if (session == null) throw StateError('新建会话未返回试卷');
    return session;
  }

  @override
  Future<SessionRecord> submitAnswer({
    required int sessionId,
    required int questionId,
    required List<String> answers,
    int elapsed = 0,
    int usedSeconds = 0,
  }) async {
    final row = await _channel
        .invokeMapMethod<Object?, Object?>('submitStudyAnswer', {
          'sessionId': sessionId,
          'questionId': questionId,
          'answers': answers,
          'elapsed': elapsed,
          'usedSeconds': usedSeconds,
        });
    if (row == null) throw StateError('本次答案未保存');
    return SessionRecord.fromMap(row);
  }

  @override
  Future<Session> retryGroup(int sessionId, int groupId) async {
    final session = await _sessionCall('retryStudyGroup', {
      'sessionId': sessionId,
      'groupId': groupId,
    });
    if (session == null) throw StateError('重试后的试卷未保存');
    return session;
  }

  @override
  Future<void> saveQuestionDistractors({
    required int sessionId,
    required int questionId,
    required List<String> distractors,
    required List<Map<String, Object?>> sources,
  }) => _channel.invokeMethod<void>('saveQuestionDistractors', {
    if (StudyOpenTiming.current case final timing?) '_open_trace_id': timing.id,
    'sessionId': sessionId,
    'questionId': questionId,
    'distractors': distractors,
    'sources': sources,
  });

  @override
  Future<void> savePlayback({
    required int sessionId,
    required int cursor,
    required int elapsed,
    required Map<String, Object?> playback,
  }) => _channel.invokeMethod<void>('updateSessionProgress', {
    'id': sessionId,
    'cursor': cursor,
    'elapsed': elapsed,
    'playback': playback,
  });

  // ---- 复习词库 ---------------------------------------------------------

  @override
  Future<WordSet?> getLatestWordSet(String date) async {
    final row = await _channel.invokeMapMethod<Object?, Object?>(
      'getLatestWordSet',
      <String, Object?>{'date': date},
    );
    // null 表示当天还没建过词库，这是正常状态而不是错误。
    if (row == null) return null;
    return WordSet.fromMap(row);
  }

  // ---- 会话 -------------------------------------------------------------

  @override
  Future<Session?> getLatestSession(ReviewModule module, String date) =>
      _readSession('getLatestSession', module, date);

  @override
  Future<Session?> getCompletedDailySession(ReviewModule module, String date) =>
      _readSession('getCompletedDailySession', module, date);

  ///
  /// 两个「取一局会话」的方法只有原生方法名不同，读取逻辑完全一致。
  Future<Session?> _readSession(
    String method,
    ReviewModule module,
    String date,
  ) => _sessionCall(method, {'module': module.storageKey, 'date': date});

  @override
  Future<Map<ReviewModule, ReviewModuleState>> getTodayModuleStates(
    String date,
  ) async {
    final rows = await _channel.invokeListMethod<Object?>(
      'getTodaySessionStates',
      <String, Object?>{'date': date},
    );
    final states = <ReviewModule, ReviewModuleState>{};
    if (rows == null) return states;
    for (final row in rows) {
      // 跳过类型不正确的元素，避免一条坏数据牵连整个首页。
      if (row is! Map) continue;
      final map = Map<Object?, Object?>.from(row);
      // 历史遗留或未知的模块键直接跳过，不能把进度记到错误的卡片上。
      final module = ReviewModule.tryFromStorageKey(map['module']?.toString());
      if (module == null) continue;
      states[module] = ReviewModuleState.fromMap(map);
    }
    return states;
  }

  @override
  Future<void> updateProgress({
    required int sessionId,
    required int cursor,
    required int elapsed,
    Map<int, int> questionTimes = const <int, int>{},
  }) => _channel.invokeMethod<void>('updateSessionProgress', <String, Object?>{
    'id': sessionId,
    'cursor': cursor,
    'elapsed': elapsed,
    'questionTimes': questionTimes.map(
      (id, seconds) => MapEntry(id.toString(), seconds),
    ),
  });

  @override
  Future<void> finishSession({
    required int sessionId,
    required SessionStatus status,
    int? cursor,
    int? elapsed,
    bool pendingSettlement = false,
  }) => _channel.invokeMethod<void>('finishSession', <String, Object?>{
    'id': sessionId,
    'status': status.code,
    'cursor': cursor,
    'elapsed': elapsed,
    'pendingSettlement': pendingSettlement,
  });

  @override
  Future<int> recoverPendingSettlements() async {
    final count = await _channel.invokeMethod<int>('recoverPendingSettlements');
    return count ?? 0;
  }

  @override
  Future<int> abortStaleSessions(String today) async {
    final count = await _channel.invokeMethod<int>(
      'abortStaleSessions',
      <String, Object?>{'date': today},
    );
    // 原生空返回按 0 处理，启动流程不应因清理失败而中断。
    return count ?? 0;
  }

  @override
  Future<int> abortActiveSessions() async {
    final count = await _channel.invokeMethod<int>('abortActiveSessions');
    // 原生空返回按 0 处理，改设置的流程不应因此中断。
    return count ?? 0;
  }

  // ---- 会话记录 ---------------------------------------------------------

  @override
  Future<SettleResult> prepareSettlement({
    required int sessionId,
    required int wordId,
  }) async {
    final row = await _channel.invokeMapMethod<Object?, Object?>(
      'prepareSettlement',
      <String, Object?>{'sessionId': sessionId, 'wordId': wordId},
    );
    if (row == null) throw StateError('原生没有返回单词结算建议');
    return SettleResult.fromMap(row);
  }

  @override
  Future<void> updateSettlementDraft({
    required int sessionId,
    required int wordId,
    required int difficultyAfter,
    required int adjustment,
    required int operation,
  }) => _channel.invokeMethod<void>('updateSettlementDraft', <String, Object?>{
    'sessionId': sessionId,
    'wordId': wordId,
    'difficultyAfter': difficultyAfter,
    'adjustment': adjustment,
    'operation': operation,
  });

  @override
  Future<List<SettlementDraft>> getSettlementDrafts(int sessionId) async {
    final rows = await _channel.invokeListMethod<Object?>(
      'getSettlementDrafts',
      <String, Object?>{'sessionId': sessionId},
    );
    if (rows == null) return const <SettlementDraft>[];
    return List<SettlementDraft>.unmodifiable(
      rows.whereType<Map>().map(
        (row) => _settlementDraftFromMap(Map<Object?, Object?>.from(row)),
      ),
    );
  }

  @override
  Future<void> finalizeSessionSettlement(int sessionId) =>
      _channel.invokeMethod<void>(
        'finalizeSessionSettlement',
        <String, Object?>{'sessionId': sessionId},
      );

  SettlementDraft _settlementDraftFromMap(Map<Object?, Object?> map) {
    int readInt(String key) {
      final value = map[key];
      return value is num ? value.toInt() : 0;
    }

    int clampInt(int value, int min, int max) => value.clamp(min, max).toInt();

    final recent = map['recent_results'];

    return SettlementDraft(
      sessionId: readInt('session_id'),
      wordId: readInt('word_id'),
      isCorrect: readInt('is_correct') == 1,
      streak: readInt('streak'),
      difficultyBefore: readInt('difficulty_before') < 0
          ? 0
          : readInt('difficulty_before'),
      suggestedAdjustment: clampInt(readInt('suggested_adjustment'), -1, 1),
      adjustment: clampInt(readInt('adjustment'), -1, 1),
      manual: readInt('operation') == 2,
      usedTimeSeconds: clampInt(readInt('used_time'), 0, 1 << 30),
      recentResults: recent is List
          ? <bool?>[
              for (final item in recent.take(5))
                if (item is bool)
                  item
                else if (item is num)
                  item.toInt() == 1
                else
                  null,
            ]
          : <bool?>[readInt('is_correct') == 1, null, null, null, null],
    );
  }

  @override
  Future<List<SessionRecord>> getSessionRecords(int sessionId) async {
    final rows = await _channel.invokeListMethod<Object?>(
      'getSessionRecords',
      <String, Object?>{'sessionId': sessionId},
    );
    if (rows == null) return const <SessionRecord>[];
    final records = <SessionRecord>[];
    for (final row in rows) {
      // 跳过类型不正确的元素，避免一条坏数据让整局无法恢复。
      if (row is! Map) continue;
      records.add(SessionRecord.fromMap(Map<Object?, Object?>.from(row)));
    }
    // 冻结列表，防止页面直接修改 Store 返回的顺序。
    return List<SessionRecord>.unmodifiable(records);
  }

  // ---- 统计 -------------------------------------------------------------

  @override
  Future<int> getTodayReviewedWordCount(String date) async {
    final count = await _channel.invokeMethod<int>(
      'getTodayReviewedWordCount',
      <String, Object?>{'date': date},
    );
    // 原生空返回按 0 处理，避免首页统计中断。
    return count ?? 0;
  }

  @override
  Future<List<int>> getTodayReviewedWordIds(String date) async {
    final ids = await _channel.invokeListMethod<int>(
      'getTodayReviewedWordIds',
      <String, Object?>{'date': date},
    );
    return ids == null ? const <int>[] : List<int>.unmodifiable(ids);
  }

  @override
  Future<Map<String, int>> getDailyCounts({
    String? since,
    bool correctOnly = false,
  }) async {
    final rows = await _channel.invokeListMethod<Object?>(
      'getDailyCounts',
      <String, Object?>{'since': since, 'correctOnly': correctOnly},
    );
    return _readCounts(rows, 'date');
  }

  @override
  Future<Map<String, int>> getDailyDurations({String? since}) async {
    final rows = await _channel.invokeListMethod<Object?>(
      'getDailyDurations',
      <String, Object?>{'since': since},
    );
    return _readCounts(rows, 'date');
  }

  @override
  Future<Map<String, int>> getMonthlyCounts({String? since}) async {
    final rows = await _channel.invokeListMethod<Object?>(
      'getMonthlyCounts',
      <String, Object?>{'since': since},
    );
    return _readCounts(rows, 'month');
  }

  ///
  /// 把原生返回的 [{键: 值, count: n}] 列表整理成按键索引的 Map。
  Map<String, int> _readCounts(List<Object?>? rows, String keyField) {
    final counts = <String, int>{};
    if (rows == null) return counts;
    for (final row in rows) {
      // 跳过类型不正确的元素，避免异常数据牵连整个统计。
      if (row is! Map) continue;
      final key = row[keyField];
      final count = row['count'];
      if (key is! String || count is! num) continue;
      counts[key] = count.toInt();
    }
    return counts;
  }
}

Map<String, Object?> _sessionArguments(Map<String, Object?> arguments) {
  final words = arguments['words'];
  if (words is! List<Word>) return arguments;
  return <String, Object?>{
    ...arguments,
    'words': words.map((word) => word.toMap()).toList(),
  };
}

ByteData _encodeSessionCall(
  ({String method, Map<String, Object?> arguments}) input,
) => const StandardMethodCodec().encodeMethodCall(
  MethodCall(input.method, _sessionArguments(input.arguments)),
);

Session? _decodeSessionReply(ByteData reply) {
  final decoded = const StandardMethodCodec().decodeEnvelope(reply);
  return decoded == null
      ? null
      : Session.fromMap(Map<Object?, Object?>.from(decoded as Map));
}
