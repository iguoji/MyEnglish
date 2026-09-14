import 'dart:math';

import '../../../models/session.dart';
import '../../../models/session_record.dart';
import '../../../models/word.dart';
import '../../../models/word_set.dart';
import '../../../store/session.dart';
import '../../../store/word.dart';
import '../../../services/study_open_timing.dart';
import '../../../services/self_test_policy.dart';
import 'question_builder.dart';

/// 一个入口返回整局试卷、开局词库和当前遍次的答案，页面无需再拼接现有词库。
class ReviewEntry {
  const ReviewEntry({
    required this.session,
    required this.words,
    required this.records,
  });
  final Session session;
  final Map<int, Word> words;
  final List<SessionRecord> records;
  bool get isFresh => records.isEmpty && session.cursor == 0;
}

/// 首页与自测共用开局流程；计划会变化，已经建立的试卷保持固定。
class ReviewFlow {
  ReviewFlow({
    required this.wordStore,
    required this.sessionStore,
    Random? random,
  }) : _random = random ?? Random();
  final WordStore wordStore;
  final SessionStore sessionStore;
  final Random _random;
  static const double primaryRatio = 0.4;

  Future<List<int>> pickTwoLayer({
    required int limit,
    List<int> exclude = const <int>[],
  }) async {
    if (limit <= 0) return const [];
    final hard = await wordStore.pickWords(
      limit: (limit * primaryRatio).ceil(),
      exclude: exclude,
      layer: PickLayer.hard,
    );
    final stale = await wordStore.pickWords(
      limit: limit - hard.length,
      exclude: <int>[...exclude, ...hard],
      layer: PickLayer.stale,
    );
    return <int>[...hard, ...stale];
  }

  /// libraryCount 仅保留调用兼容；实际补缺直接读取数据库，首页缓存不会限制新词。
  Future<WordSet?> resolveWordSet({
    required int dailyGoal,
    required int libraryCount,
    required String date,
  }) => sessionStore.resolvePlan(date: date, dailyGoal: dailyGoal);

  Future<ReviewEntry?> openModule(
    ReviewModule module, {
    required int dailyGoal,
    required int libraryCount,
    required String date,
  }) async {
    await sessionStore.recoverPendingSettlements();
    final active = await sessionStore.getActiveSession(module, date);
    if (active != null) return _entry(active);
    final plan = await sessionStore.resolvePlan(
      date: date,
      dailyGoal: dailyGoal,
    );
    if (plan == null || plan.todayWordIds.isEmpty || dailyGoal <= 0) {
      return null;
    }
    final completed = await sessionStore.getCompletedDailySession(module, date);
    final kind = completed == null ? SessionKind.daily : SessionKind.reinforce;
    final ids = kind == SessionKind.daily
        ? _interleave(plan)
        : _reinforce(plan, dailyGoal);
    return _create(module, kind, ids, date, plan.id);
  }

  /// 明确选词必定新建自测；恢复由 resumeSelf 独立处理，不会重新传入选词。
  ///
  /// [preloaded] 是调用方手上已经拿到的单词对象（首页词库列表就是）。传了它
  /// 就不再去数据库按编号捞一遍——从词库底部随手开一局时，这一趟等于把整库
  /// 上千个单词再读一次，白白多花掉用户等待的一部分时间。
  Future<ReviewEntry?> openAdHoc(
    ReviewModule module, {
    required List<int> wordIds,
    required String date,
    List<Word> preloaded = const <Word>[],
  }) async {
    if (wordIds.isEmpty) return null;
    if (module == ReviewModule.listening) {
      throw ArgumentError('随身听使用独立播放列表，不创建复习会话');
    }
    final selectedIds = wordIds.toSet().toList(growable: false);
    final reason = SelfTestPolicy.unavailableReason(selectedIds.length);
    if (reason != null) throw ArgumentError(reason);
    // 新建与中断旧自测由数据库在同一个事务完成；新建失败仍保留旧进度。
    return _create(
      module,
      SessionKind.selfTest,
      selectedIds,
      date,
      null,
      preloaded: preloaded,
    );
  }

  Future<ReviewEntry?> resumeSelf(ReviewModule module, String date) async {
    final session = await sessionStore.getActiveSession(
      module,
      date,
      selfTest: true,
    );
    return session == null ? null : _entry(session);
  }

  Future<ReviewEntry?> _create(
    ReviewModule module,
    SessionKind kind,
    List<int> ids,
    String date,
    int? planId, {
    List<Word> preloaded = const <Word>[],
  }) async {
    if (ids.isEmpty) return null;
    // 调用方已经给过单词对象就直接用，省掉一次「按编号把整库读回来」。
    final source = preloaded.isEmpty
        ? await wordStore.getByIds(ids)
        : preloaded;
    final byId = <int, Word>{
      for (final word in source)
        if (word.id != null) word.id!: word,
    };
    final words = <Word>[
      for (final id in ids)
        if (byId[id] != null) byId[id]!,
    ];
    if (words.isEmpty) return null;
    // 编号对应的词可能刚被删除，按实际能够进入试卷的数量再核对一次。
    if (kind == SessionKind.selfTest) {
      final reason = SelfTestPolicy.unavailableReason(words.length);
      if (reason != null) throw ArgumentError(reason);
    }
    final timing = StudyOpenTiming.current;
    timing?.mark('targets_ready');
    final groups = await ReviewQuestionBuilder.buildAsync(
      module,
      words,
      random: _random,
    );
    timing?.mark('paper_ready');
    if (groups.isEmpty) return null;
    final session = await sessionStore.createStudySession(
      module: module,
      kind: kind,
      planId: planId,
      words: words,
      groups: groups,
      date: date,
    );
    timing?.attach(session);
    final entry = _entry(session);
    timing?.mark('entry_ready');
    return entry;
  }

  ReviewEntry _entry(Session session) => ReviewEntry(
    session: session,
    words: <int, Word>{
      for (final word in session.snapshotWords) word.id!: word,
    },
    records: session.records,
  );

  List<int> _interleave(WordSet plan) {
    final hardSet = plan.hardWordIds.toSet();
    final hard = plan.todayWordIds.where(hardSet.contains).toList();
    final stale = plan.todayWordIds
        .where((id) => !hardSet.contains(id))
        .toList();
    final result = <int>[];
    var h = 0;
    var s = 0;
    for (var position = 0; position < plan.todayWordIds.length; position++) {
      final desired = ((position + 1) * hard.length / plan.todayWordIds.length)
          .round();
      if (h < hard.length && (h < desired || s >= stale.length)) {
        result.add(hard[h++]);
      } else if (s < stale.length) {
        result.add(stale[s++]);
      }
    }
    return result;
  }

  /// 各取一半后，先补剩余明日词，再补剩余今日词；整局同一个词只出现一次。
  List<int> _reinforce(WordSet plan, int target) {
    final today = List<int>.of(plan.todayWordIds)..shuffle(_random);
    final tomorrow = List<int>.of(plan.tomorrowWordIds)..shuffle(_random);
    final selected = <int>{};
    void take(Iterable<int> source, int count) {
      var added = 0;
      for (final id in source) {
        if (selected.length >= target || added >= count) break;
        if (selected.add(id)) added++;
      }
    }

    take(today, (target / 2).ceil());
    take(tomorrow, target ~/ 2);
    take(tomorrow, target - selected.length);
    take(today, target - selected.length);
    return selected.toList()..shuffle(_random);
  }
}
