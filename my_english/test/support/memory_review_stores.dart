import 'dart:convert';

import 'package:my_english/models/daily_word_set.dart';
import 'package:my_english/models/review_session.dart';
import 'package:my_english/store/daily_word_set.dart';
import 'package:my_english/store/review_session.dart';

///
/// 每日词库的内存测试实现。
///
/// 行为与 SQLite 版一致：一天只保留一份，保存时按日期覆盖。
///
class MemoryDailyWordSetStore implements DailyWordSetStore {
  ///
  /// 创建测试使用的内存词库 Store。
  MemoryDailyWordSetStore({DailyWordSet? initial, String? today})
    : current = initial,
      _today = today ?? _defaultToday();

  ///
  /// 当前内存中的今日词库；null 表示今天还没建过。
  DailyWordSet? current;

  ///
  /// 测试固定的「今天」，格式 yyyy-MM-dd。
  final String _today;

  ///
  /// saveToday 被调用的次数，用于断言「没有必要就不该重写词库」。
  int saveCount = 0;

  @override
  Future<DailyWordSet?> getToday() async {
    // 日期对不上就等于今天还没建过，模拟原生按日期过滤的行为。
    final wordSet = current;
    if (wordSet == null || wordSet.setDate != _today) return null;
    return wordSet;
  }

  @override
  Future<DailyWordSet> saveToday(List<int> wordIds) async {
    // 与正式 Store 一致：空列表无法支撑任何一局复习。
    if (wordIds.isEmpty) {
      throw ArgumentError.value(wordIds, 'wordIds', '每日词库单词列表不能为空');
    }
    saveCount += 1;
    // 已有词库就保留自增 id，模拟原生「就地更新、不换主键」的行为。
    final saved = DailyWordSet(
      id: current?.id ?? 1,
      setDate: _today,
      wordCount: wordIds.length,
      wordIds: List<int>.unmodifiable(wordIds),
    );
    current = saved;
    return saved;
  }

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
/// 复习会话的内存测试实现。
///
/// 行为与 SQLite 版一致：同模块新建会话前先把残留的进行中会话改成中断，
/// 「最新一条」永远取 id 最大的那条。
///
class MemoryReviewSessionStore implements ReviewSessionStore {
  ///
  /// 创建测试使用的内存会话 Store。
  MemoryReviewSessionStore({
    List<ReviewSession> initial = const <ReviewSession>[],
    String? today,
  }) : sessions = List<ReviewSession>.of(initial),
       _today = today ?? MemoryDailyWordSetStore._defaultToday();

  ///
  /// 当前内存中的全部会话，按创建顺序排列。
  final List<ReviewSession> sessions;

  ///
  /// 测试固定的「今天」，格式 yyyy-MM-dd。
  final String _today;

  ///
  /// 下一条会话使用的自增主键。
  int _nextId = 1;

  @override
  Future<ReviewSession?> getLatest(ReviewModule module) async {
    // 倒序查找等价于 SQL 的 ORDER BY id DESC LIMIT 1。
    for (final session in sessions.reversed) {
      if (session.module == module && session.sessionDate == _today) {
        return session;
      }
    }
    return null;
  }

  @override
  Future<ReviewSession?> getCompletedDaily(ReviewModule module) async {
    for (final session in sessions.reversed) {
      if (session.module == module &&
          session.sessionDate == _today &&
          session.kind == ReviewSessionKind.daily &&
          session.status == ReviewSessionStatus.completed) {
        return session;
      }
    }
    return null;
  }

  @override
  Future<Map<ReviewModule, ReviewModuleState>> getTodayStates() async {
    final states = <ReviewModule, ReviewModuleState>{};
    for (final module in ReviewModule.values) {
      final latest = await getLatest(module);
      if (latest == null) continue;
      final completed = await getCompletedDaily(module);
      states[module] = ReviewModuleState.fromMap(<Object?, Object?>{
        'module': module.storageKey,
        'kind': latest.kind.code,
        'status': latest.status.code,
        'daily_completed': completed != null,
      });
    }
    return Map<ReviewModule, ReviewModuleState>.unmodifiable(states);
  }

  @override
  Future<ReviewSession> create({
    required ReviewModule module,
    required ReviewSessionKind kind,
    required int? wordSetId,
    required List<int> wordIds,
    Map<String, Object?> state = const <String, Object?>{},
  }) async {
    if (wordIds.isEmpty) {
      throw ArgumentError.value(wordIds, 'wordIds', '复习会话单词列表不能为空');
    }
    // 同模块残留的进行中会话先收尾，保证「最新一条」的语义永远干净。
    for (var index = 0; index < sessions.length; index += 1) {
      final item = sessions[index];
      if (item.module == module && item.status == ReviewSessionStatus.active) {
        sessions[index] = _copyWith(item, status: ReviewSessionStatus.aborted);
      }
    }
    final session = ReviewSession(
      id: _nextId++,
      module: module,
      kind: kind,
      status: ReviewSessionStatus.active,
      wordSetId: wordSetId,
      wordIds: List<int>.unmodifiable(wordIds),
      // 走一遍 JSON 编解码，暴露测试里塞进不可序列化对象的问题。
      state: Map<String, Object?>.unmodifiable(
        (jsonDecode(jsonEncode(state)) as Map).cast<String, Object?>(),
      ),
      wrongTotal: 0,
      sessionDate: _today,
      createdAt: DateTime.now(),
    );
    sessions.add(session);
    return session;
  }

  @override
  Future<void> saveProgress({
    required int sessionId,
    required Map<String, Object?> state,
    required int wrongTotal,
  }) async {
    final index = sessions.indexWhere((item) => item.id == sessionId);
    if (index < 0) return;
    // 与原生一致：只允许改「进行中」的会话。
    if (sessions[index].status != ReviewSessionStatus.active) return;
    sessions[index] = _copyWith(
      sessions[index],
      state: (jsonDecode(jsonEncode(state)) as Map).cast<String, Object?>(),
      wrongTotal: wrongTotal < 0 ? 0 : wrongTotal,
    );
  }

  @override
  Future<ReviewSession> finish({
    required int sessionId,
    required ReviewSessionStatus status,
    Map<String, Object?>? state,
    int? wrongTotal,
  }) async {
    if (status == ReviewSessionStatus.active) {
      throw ArgumentError.value(status, 'status', '结算状态不能是进行中');
    }
    final index = sessions.indexWhere((item) => item.id == sessionId);
    if (index < 0) throw StateError('会话 $sessionId 不存在');
    final current = sessions[index];
    // 与原生一致：只结算尚未结算的局，重复调用不会把状态改来改去。
    if (current.status != ReviewSessionStatus.active) return current;
    final settled = _copyWith(
      current,
      status: status,
      state: state == null
          ? null
          : (jsonDecode(jsonEncode(state)) as Map).cast<String, Object?>(),
      wrongTotal: wrongTotal,
      finishedAt: DateTime.now(),
    );
    sessions[index] = settled;
    return settled;
  }

  @override
  Future<int> abortActive({bool onlyStale = false}) async {
    var count = 0;
    for (var index = 0; index < sessions.length; index += 1) {
      final item = sessions[index];
      if (item.status != ReviewSessionStatus.active) continue;
      // onlyStale 只收「不是今天」的局，今天的进度完整保留。
      if (onlyStale && item.sessionDate == _today) continue;
      sessions[index] = _copyWith(
        item,
        status: ReviewSessionStatus.aborted,
        finishedAt: DateTime.now(),
      );
      count += 1;
    }
    return count;
  }

  ///
  /// 生成一份只改动指定字段的会话副本。
  ///
  /// 模型本身不可变，内存 Store 用它模拟数据库的原地更新。
  ReviewSession _copyWith(
    ReviewSession session, {
    ReviewSessionStatus? status,
    Map<String, Object?>? state,
    int? wrongTotal,
    DateTime? finishedAt,
  }) {
    return ReviewSession(
      id: session.id,
      module: session.module,
      kind: session.kind,
      status: status ?? session.status,
      wordSetId: session.wordSetId,
      wordIds: session.wordIds,
      state: state == null
          ? session.state
          : Map<String, Object?>.unmodifiable(state),
      wrongTotal: wrongTotal ?? session.wrongTotal,
      sessionDate: session.sessionDate,
      createdAt: session.createdAt,
      updatedAt: DateTime.now(),
      finishedAt: finishedAt ?? session.finishedAt,
    );
  }
}
