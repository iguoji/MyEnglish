import 'dart:math';

import '../../../models/session.dart';
import '../../../models/session_record.dart';
import '../../../models/word.dart';
import '../../../models/word_set.dart';
import '../../../store/session.dart';
import '../../../store/word.dart';
import '../../../services/app_log.dart';
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
    Random? distractorRandom,
  }) : _random = random ?? Random(),
       _distractorRandom = distractorRandom ?? Random();
  final WordStore wordStore;
  final SessionStore sessionStore;
  final Random _random;

  /// 每局挑混淆项用的随机源；与选词、编题的 [_random] 分开，互不影响。
  final Random _distractorRandom;

  /// libraryCount 仅保留调用兼容；实际补缺直接读取数据库，首页缓存不会限制新词。
  Future<WordSet?> resolveWordSet({
    required int dailyGoal,
    required int libraryCount,
    required String date,
  }) => sessionStore.resolvePlan(date: date, dailyGoal: dailyGoal);

  /// [corpusWords] 是首页手上的全局词库，开局时从里面给选择题挑混淆项；
  /// 不传时自己去数据库读一次。
  Future<ReviewEntry?> openModule(
    ReviewModule module, {
    required int dailyGoal,
    required int libraryCount,
    required String date,
    List<Word> corpusWords = const <Word>[],
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
    return _create(module, kind, ids, date, plan.id, corpusWords: corpusWords);
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
    List<Word> corpusWords = const <Word>[],
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
      corpusWords: corpusWords,
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
    List<Word> corpusWords = const <Word>[],
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
    // 听音辨义、看义选词是选择题：开局时就从全局词库给整局挑好混淆项，
    // 保证整局尽量不重复、答案位置均匀，恢复会话时原样读出。
    final hasChoices =
        module == ReviewModule.listeningMeaning ||
        module == ReviewModule.meaningWordChoice;
    final groups = await ReviewQuestionBuilder.buildAsync(
      module,
      words,
      random: _random,
      corpus: hasChoices ? await _corpusFor(corpusWords, words) : null,
      distractorSeed: _distractorRandom.nextInt(0x7fffffff),
    );
    timing?.mark('paper_ready');
    if (groups.isEmpty) return null;
    _logPaper(module, words.length, groups);
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

  /// 试卷一编好就把结构记进日志：几道大题、各有几小题、哪些大题没排满。
  /// 事后追查「某一大题为什么只有三张」时，能直接对上当时的试卷，不用猜。
  void _logPaper(
    ReviewModule module,
    int wordCount,
    List<Map<String, Object?>> groups,
  ) {
    final sizes = <int>[
      for (final group in groups)
        (group['questions']! as List<Map<String, Object?>>).length,
    ];
    final total = sizes.fold<int>(0, (sum, size) => sum + size);
    // 连续相同的张数压成「5×47」，试卷再长也只占一行。
    final runs = <String>[];
    for (var i = 0; i < sizes.length;) {
      var j = i;
      while (j < sizes.length && sizes[j] == sizes[i]) {
        j++;
      }
      runs.add(j - i == 1 ? '${sizes[i]}' : '${sizes[i]}×${j - i}');
      i = j;
    }
    // 词义连连要求「除最后一大题外每题一样多」；不满足就单独点名，方便一眼看出。
    final expected = sizes.isEmpty ? 0 : sizes.reduce(max);
    final short = <int>[
      for (var i = 0; i < sizes.length - 1; i++)
        if (sizes[i] != expected) i + 1,
    ];
    AppLog.i(
      'study_paper',
      '出题 module=${module.storageKey} words=$wordCount 大题=${sizes.length} '
          '小题=$total 各大题小题数=${runs.join(',')}'
          '${short.isEmpty ? '' : ' 中间没排满的大题=$short'}',
    );
  }

  /// 挑混淆项用的全局词库：优先用首页手上那份，没有再读数据库，读不到就用本局单词。
  Future<List<Word>> _corpusFor(List<Word> preferred, List<Word> words) async {
    if (preferred.isNotEmpty) return preferred;
    try {
      final all = await wordStore.getAll();
      return all.isEmpty ? words : all;
    } catch (_) {
      return words;
    }
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
