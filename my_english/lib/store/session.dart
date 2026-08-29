// convert.dart 提供 jsonEncode，把数据列表编码成原生保存的 JSON 文本。
import 'dart:convert';

// services.dart 提供 MethodChannel，让 Dart 调用 Android 原生 SQLite。
import 'package:flutter/services.dart';

// 会话、记录与词库三个模型都由本 Store 负责读写。
import '../models/session.dart';
import '../models/session_record.dart';
import '../models/word_set.dart';

///
/// 会话 Store 接口：复习词库、会话、会话记录与统计的读写契约。
///
/// 这四块放在一个 Store 里，是因为它们在业务上是同一条链路：
/// 「今天挑哪批词 → 开哪一局 → 每点一次记一笔 → 汇总成首页的数字」。
/// 拆开只会让页面同时持有四个 Store，却永远一起用。
///
abstract interface class SessionStore {
  // ---- 复习词库 ---------------------------------------------------------

  ///
  /// 取某天最新的一份词库；当天还没建过则返回 null。
  Future<WordSet?> getLatestWordSet(String date);

  ///
  /// 新建一份词库，返回主键。
  ///
  /// [wordCount] 是创建时「每日复习」设置的数量，用来和之后的设置比对。
  Future<int> createWordSet({
    required int wordCount,
    required List<int> todayWordIds,
    required List<int> tomorrowWordIds,
    required String date,
  });

  // ---- 会话 -------------------------------------------------------------

  ///
  /// 取某模块某天最新的一局；没有则返回 null。
  Future<Session?> getLatestSession(ReviewModule module, String date);

  ///
  /// 取某模块某天「已完成的主线会话」，用来判断今日任务过没过关。
  Future<Session?> getCompletedDailySession(ReviewModule module, String date);

  ///
  /// 一次读出今天全部模块的三态进度，供首页渲染卡片。
  ///
  /// 今天没开过局的模块不会出现在返回值里，调用方按「待完成」补齐。
  Future<Map<ReviewModule, ReviewModuleState>> getTodayModuleStates(String date);

  ///
  /// 新建一局会话，返回主键。
  ///
  /// [items] 是这一局固定的答题顺序，元素形状按模块而定：
  /// 一维主键数组，或 `[[单词id, 含义id], ...]` 这样的数对数组。
  Future<int> createSession({
    required ReviewModule module,
    required SessionKind kind,
    required int? wordSetId,
    required List<Object?> items,
    required String date,
  });

  ///
  /// 保存这一局的进度：做到第几条、已经花了多少秒。
  Future<void> updateProgress({
    required int sessionId,
    required int cursor,
    required int elapsed,
  });

  ///
  /// 给这一局判成败。
  Future<void> finishSession({
    required int sessionId,
    required SessionStatus status,
    int? cursor,
    int? elapsed,
  });

  ///
  /// 中断「不是今天」的进行中会话，返回被中断的局数。
  ///
  /// 跨天后昨天没打完的局挂着没有意义——今天有今天的词库。
  /// 今天的进度完整保留。
  Future<int> abortStaleSessions(String today);

  ///
  /// 中断全部进行中的会话，返回被中断的局数。
  ///
  /// 用户改了「每日复习」数量时调用：今天这批词的数量变了，
  /// 正在进行的每一局都对不上新词库，只能整体作废重来。
  Future<int> abortActiveSessions();

  // ---- 会话记录 ---------------------------------------------------------

  ///
  /// 记一次点击，不论对错。
  ///
  /// [meaningId] 为空表示这一步针对整个单词（听音辨义的「选拼写」）。
  /// [input] 是用户实际点的那个候选词，或者拼错的完整单词。
  Future<void> addRecord({
    required int sessionId,
    required int wordId,
    int? meaningId,
    required String input,
    required bool isCorrect,
  });

  ///
  /// 一个单词在本局整个过完一遍后结算：更新难度，必要时推进复习时间。
  ///
  /// 判定口径是「本局本词有没有点错过」——一次都没错才算这一轮答对。
  Future<SettleResult> settleWord({
    required int sessionId,
    required int wordId,
    required bool updateReviewedAt,
  });

  ///
  /// 读取一局的全部记录，供中途退出后还原现场。
  Future<List<SessionRecord>> getSessionRecords(int sessionId);

  // ---- 统计 -------------------------------------------------------------

  ///
  /// 今天「一次做对」过的不同单词数。
  ///
  /// 口径：这个词今天有过记录，且今天从来没在任何一局里点错过。
  /// 首页副标题「今日复习 X / 目标」用的就是它。
  Future<int> getTodayCorrectWordCount(String date);

  ///
  /// 今天「一次做对」过的不同单词主键，供首页明细列表使用。
  Future<List<int>> getTodayCorrectWordIds(String date);

  ///
  /// 按天统计单词数（每天按单词去重）。
  ///
  /// [correctOnly] 为 true 时只算「这一天一次都没错过」的词（趋势曲线的掌握量）；
  /// 为 false 时不论对错，练了就算（打卡热力图的复习总数）。
  /// 没有记录的日期不会出现在结果里，调用方按需补 0。
  Future<Map<String, int>> getDailyCounts({String? since, bool correctOnly});

  ///
  /// 按月统计复习单词数（每月按单词去重）。
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

  @override
  Future<int> createWordSet({
    required int wordCount,
    required List<int> todayWordIds,
    required List<int> tomorrowWordIds,
    required String date,
  }) async {
    final id = await _channel.invokeMethod<int>(
      'createWordSet',
      <String, Object?>{
        'wordCount': wordCount,
        'todayWordIds': todayWordIds,
        'tomorrowWordIds': tomorrowWordIds,
        'date': date,
      },
    );
    if (id == null) throw StateError('SQLite 创建复习词库后没有返回主键');
    return id;
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
  ) async {
    final row = await _channel.invokeMapMethod<Object?, Object?>(
      method,
      <String, Object?>{'module': module.storageKey, 'date': date},
    );
    if (row == null) return null;
    return Session.fromMap(row);
  }

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
  Future<int> createSession({
    required ReviewModule module,
    required SessionKind kind,
    required int? wordSetId,
    required List<Object?> items,
    required String date,
  }) async {
    final id = await _channel.invokeMethod<int>(
      'createSession',
      <String, Object?>{
        'module': module.storageKey,
        'kind': kind.code,
        'wordSetId': wordSetId,
        // 数据列表的元素形状因模块而异，统一编码成 JSON 文本再存。
        'itemsJson': jsonEncode(items),
        'date': date,
      },
    );
    if (id == null) throw StateError('SQLite 创建会话后没有返回主键');
    return id;
  }

  @override
  Future<void> updateProgress({
    required int sessionId,
    required int cursor,
    required int elapsed,
  }) => _channel.invokeMethod<void>('updateSessionProgress', <String, Object?>{
    'id': sessionId,
    'cursor': cursor,
    'elapsed': elapsed,
  });

  @override
  Future<void> finishSession({
    required int sessionId,
    required SessionStatus status,
    int? cursor,
    int? elapsed,
  }) => _channel.invokeMethod<void>('finishSession', <String, Object?>{
    'id': sessionId,
    'status': status.code,
    'cursor': cursor,
    'elapsed': elapsed,
  });

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
  Future<void> addRecord({
    required int sessionId,
    required int wordId,
    int? meaningId,
    required String input,
    required bool isCorrect,
  }) => _channel.invokeMethod<void>('addRecord', <String, Object?>{
    'sessionId': sessionId,
    'wordId': wordId,
    'meaningId': meaningId,
    'input': input,
    'result': isCorrect ? 1 : 0,
  });

  @override
  Future<SettleResult> settleWord({
    required int sessionId,
    required int wordId,
    required bool updateReviewedAt,
  }) async {
    final row = await _channel.invokeMapMethod<Object?, Object?>(
      'settleWord',
      <String, Object?>{
        'sessionId': sessionId,
        'wordId': wordId,
        'updateReviewedAt': updateReviewedAt,
      },
    );
    if (row == null) throw StateError('原生没有返回单词结算结果');
    return SettleResult.fromMap(row);
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
  Future<int> getTodayCorrectWordCount(String date) async {
    final count = await _channel.invokeMethod<int>(
      'getTodayCorrectWordCount',
      <String, Object?>{'date': date},
    );
    // 原生空返回按 0 处理，避免首页统计中断。
    return count ?? 0;
  }

  @override
  Future<List<int>> getTodayCorrectWordIds(String date) async {
    final ids = await _channel.invokeListMethod<int>(
      'getTodayCorrectWordIds',
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
