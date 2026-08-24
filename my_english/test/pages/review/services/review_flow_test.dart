import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/review_session.dart';
import 'package:my_english/models/word.dart';
import 'package:my_english/pages/review/services/review_flow.dart';

import '../../../support/memory_review_stores.dart';

///
/// 构造一个可入库的测试单词。
Word _word(int id, {DateTime? reviewedAt}) => Word(
  id: id,
  // 拼写按编号补零，保证「拼写升序」与「编号升序」结论一致，断言更直观。
  spelling: 'w${id.toString().padLeft(3, '0')}',
  meanings: <Meaning>[
    const Meaning(index: 0, pos: 'n.', definitions: <String>['释义']),
  ],
  reviewedAt: reviewedAt,
);

///
/// 生成 [count] 个从未复习过的单词，主键从 1 开始连续。
List<Word> _words(int count) =>
    <Word>[for (var id = 1; id <= count; id += 1) _word(id)];

///
/// 组装一个使用固定随机种子的复习流程，让巩固局抽词结果可复现。
ReviewFlow _flow(
  MemoryDailyWordSetStore wordSetStore,
  MemoryReviewSessionStore sessionStore,
) => ReviewFlow(
  wordSetStore: wordSetStore,
  sessionStore: sessionStore,
  random: Random(2026),
);

///
/// 验证「创建词库」与「创建会话」两条核心流程。
void main() {
  group('创建词库', () {
    test('今天第一次进模块时按排序规则选出目标数量并落库', () async {
      final wordSetStore = MemoryDailyWordSetStore();
      final sessionStore = MemoryReviewSessionStore();
      final flow = _flow(wordSetStore, sessionStore);

      final wordSet = await flow.resolveWordSet(_words(10), dailyGoal: 4);

      expect(wordSet, isNotNull);
      expect(wordSet!.wordIds, <int>[1, 2, 3, 4]);
      expect(wordSet.wordCount, 4);
      expect(wordSetStore.saveCount, 1);
    });

    test('目标没变时直接复用今天的词库，不做多余写入', () async {
      final wordSetStore = MemoryDailyWordSetStore();
      final sessionStore = MemoryReviewSessionStore();
      final flow = _flow(wordSetStore, sessionStore);
      final words = _words(10);

      await flow.resolveWordSet(words, dailyGoal: 4);
      final second = await flow.resolveWordSet(words, dailyGoal: 4);

      expect(second!.wordIds, <int>[1, 2, 3, 4]);
      // 第二次完全复用，没有再写一遍数据库。
      expect(wordSetStore.saveCount, 1);
    });

    test('目标调小时从前面截取', () async {
      final wordSetStore = MemoryDailyWordSetStore();
      final sessionStore = MemoryReviewSessionStore();
      final flow = _flow(wordSetStore, sessionStore);
      final words = _words(10);

      await flow.resolveWordSet(words, dailyGoal: 5);
      final shrunk = await flow.resolveWordSet(words, dailyGoal: 2);

      expect(shrunk!.wordIds, <int>[1, 2]);
    });

    test('目标调大时排除已有单词再补足，绝不补出重复', () async {
      final wordSetStore = MemoryDailyWordSetStore();
      final sessionStore = MemoryReviewSessionStore();
      final flow = _flow(wordSetStore, sessionStore);

      // 先按目标 3 建库，拿到 1、2、3。
      final words = _words(10);
      await flow.resolveWordSet(words, dailyGoal: 3);

      // 关键场景：已经练过的 1、2、3 复习时间被推进，掉到排序最后面。
      // 如果补词时不排除已有 id，从头拉 2 个会拉回 4、5 之外的错误结果；
      // 更糟的情况是词库前几名仍是 1、2、3，直接补出重复。
      final now = DateTime(2026, 8, 23, 12);
      final practiced = <Word>[
        _word(1, reviewedAt: now),
        _word(2, reviewedAt: now),
        _word(3, reviewedAt: now),
        for (var id = 4; id <= 10; id += 1) _word(id),
      ];
      final grown = await flow.resolveWordSet(practiced, dailyGoal: 5);

      // 原有三个保持原顺序，末尾补上两个全新的。
      expect(grown!.wordIds, <int>[1, 2, 3, 4, 5]);
      // 没有任何单词出现两次。
      expect(grown.wordIds.toSet().length, grown.wordIds.length);
    });

    test('词库里的单词被删除后，剔除失效主键并从排序结果补足', () async {
      final wordSetStore = MemoryDailyWordSetStore();
      final sessionStore = MemoryReviewSessionStore();
      final flow = _flow(wordSetStore, sessionStore);

      await flow.resolveWordSet(_words(10), dailyGoal: 4);
      // 删掉 2 号：剩下 1、3、4，再从排序结果补一个 5。
      final remaining = <Word>[
        for (final word in _words(10))
          if (word.id != 2) word,
      ];
      final repaired = await flow.resolveWordSet(remaining, dailyGoal: 4);

      expect(repaired!.wordIds, <int>[1, 3, 4, 5]);
    });

    test('词库总量不足目标时以实际数量为准，不反复重写', () async {
      final wordSetStore = MemoryDailyWordSetStore();
      final sessionStore = MemoryReviewSessionStore();
      final flow = _flow(wordSetStore, sessionStore);
      // 只录了 3 个词，目标却设成 50。
      final words = _words(3);

      final first = await flow.resolveWordSet(words, dailyGoal: 50);
      final second = await flow.resolveWordSet(words, dailyGoal: 50);

      expect(first!.wordIds, <int>[1, 2, 3]);
      expect(second!.wordIds, <int>[1, 2, 3]);
      // 第二次没有再写一遍——这正是「目标取实际数量」要解决的浪费。
      expect(wordSetStore.saveCount, 1);
    });

    test('词库为空或目标为 0 时拿不到词库', () async {
      final wordSetStore = MemoryDailyWordSetStore();
      final sessionStore = MemoryReviewSessionStore();
      final flow = _flow(wordSetStore, sessionStore);

      expect(await flow.resolveWordSet(const <Word>[], dailyGoal: 5), isNull);
      expect(await flow.resolveWordSet(_words(5), dailyGoal: 0), isNull);
    });
  });

  group('创建会话', () {
    test('今天第一次进模块开一局主线，单词就是整份词库', () async {
      final wordSetStore = MemoryDailyWordSetStore();
      final sessionStore = MemoryReviewSessionStore();
      final flow = _flow(wordSetStore, sessionStore);

      final entry = await flow.openModule(
        ReviewModule.listeningMeaning,
        allWords: _words(10),
        dailyGoal: 4,
      );

      expect(entry, isNotNull);
      expect(entry!.session.kind, ReviewSessionKind.daily);
      expect(entry.session.status, ReviewSessionStatus.active);
      expect(entry.session.wordIds, <int>[1, 2, 3, 4]);
      // 主线会话答题要推进复习时间。
      expect(entry.session.updatesReviewedAt, isTrue);
      // 返回的单词与会话顺序严格一致。
      expect(entry.words.map((word) => word.id), <int>[1, 2, 3, 4]);
    });

    test('已有进行中的局直接续上，不会重开', () async {
      final wordSetStore = MemoryDailyWordSetStore();
      final sessionStore = MemoryReviewSessionStore();
      final flow = _flow(wordSetStore, sessionStore);
      final words = _words(10);

      final first = await flow.openModule(
        ReviewModule.listeningMeaning,
        allWords: words,
        dailyGoal: 4,
      );
      // 模拟用户做到一半退出去，进度已经落盘。
      await sessionStore.saveProgress(
        sessionId: first!.session.id,
        state: <String, Object?>{'wordIndex': 2},
        wrongTotal: 1,
      );
      final resumed = await flow.openModule(
        ReviewModule.listeningMeaning,
        allWords: words,
        dailyGoal: 4,
      );

      expect(resumed!.session.id, first.session.id);
      expect(resumed.session.state['wordIndex'], 2);
      // 累计错误数接着数，不会因为重进而归零。
      expect(resumed.session.wrongTotal, 1);
      expect(sessionStore.sessions, hasLength(1));
    });

    test('上一局失败后再进模块，重开一局主线而不是巩固', () async {
      final wordSetStore = MemoryDailyWordSetStore();
      final sessionStore = MemoryReviewSessionStore();
      final flow = _flow(wordSetStore, sessionStore);
      final words = _words(10);

      final first = await flow.openModule(
        ReviewModule.listeningMeaning,
        allWords: words,
        dailyGoal: 4,
      );
      // 整局跑完但错过 → 失败。
      await sessionStore.finish(
        sessionId: first!.session.id,
        status: ReviewSessionStatus.failed,
        wrongTotal: 2,
      );
      final retry = await flow.openModule(
        ReviewModule.listeningMeaning,
        allWords: words,
        dailyGoal: 4,
      );

      expect(retry!.session.id, isNot(first.session.id));
      expect(retry.session.kind, ReviewSessionKind.daily);
      // 重来的还是今天这批词，从头再走一遍。
      expect(retry.session.wordIds, <int>[1, 2, 3, 4]);
    });

    test('主线过关后再进模块，开一局巩固：今天一半 + 明天一半', () async {
      final wordSetStore = MemoryDailyWordSetStore();
      final sessionStore = MemoryReviewSessionStore();
      final flow = _flow(wordSetStore, sessionStore);
      final words = _words(20);

      final daily = await flow.openModule(
        ReviewModule.listeningMeaning,
        allWords: words,
        dailyGoal: 4,
      );
      // 整局跑完且一次没错 → 完成。
      await sessionStore.finish(
        sessionId: daily!.session.id,
        status: ReviewSessionStatus.completed,
        wrongTotal: 0,
      );

      // 主线过关后今天这 4 个词的复习时间已被推进，掉到排序最后面。
      final now = DateTime(2026, 8, 23, 12);
      final practiced = <Word>[
        for (final word in words)
          if (word.id! <= 4) _word(word.id!, reviewedAt: now) else word,
      ];
      final reinforce = await flow.openModule(
        ReviewModule.listeningMeaning,
        allWords: practiced,
        dailyGoal: 4,
      );

      expect(reinforce!.session.kind, ReviewSessionKind.reinforce);
      // 巩固局不推进复习时间，明天这批词才不会被提前消耗掉。
      expect(reinforce.session.updatesReviewedAt, isFalse);
      // 题量不缩水，仍是今天的目标数量。
      expect(reinforce.session.wordIds, hasLength(4));
      // 一半来自今天（1..4），一半来自明天（5..8）。
      final todayIds = <int>{1, 2, 3, 4};
      final fromToday = reinforce.session.wordIds.where(todayIds.contains);
      expect(fromToday, hasLength(2));
      expect(reinforce.session.wordIds.where((id) => id > 4), hasLength(2));
      // 同一局里不会出现重复单词。
      expect(
        reinforce.session.wordIds.toSet().length,
        reinforce.session.wordIds.length,
      );
    });

    test('词库总量不足两倍目标时，明天的词不够就由今天补足', () async {
      final wordSetStore = MemoryDailyWordSetStore();
      final sessionStore = MemoryReviewSessionStore();
      final flow = _flow(wordSetStore, sessionStore);
      // 只有 5 个词、目标 4：明天最多只能凑出 1 个。
      final words = _words(5);

      final daily = await flow.openModule(
        ReviewModule.listeningMeaning,
        allWords: words,
        dailyGoal: 4,
      );
      await sessionStore.finish(
        sessionId: daily!.session.id,
        status: ReviewSessionStatus.completed,
        wrongTotal: 0,
      );
      final reinforce = await flow.openModule(
        ReviewModule.listeningMeaning,
        allWords: words,
        dailyGoal: 4,
      );

      // 题量仍然是 4，缺口由今天的词补上，且没有重复。
      expect(reinforce!.session.wordIds, hasLength(4));
      expect(
        reinforce.session.wordIds.toSet().length,
        reinforce.session.wordIds.length,
      );
    });

    test('每日复习量改了以后，旧的进行中主线会被中断并重开', () async {
      final wordSetStore = MemoryDailyWordSetStore();
      final sessionStore = MemoryReviewSessionStore();
      final flow = _flow(wordSetStore, sessionStore);
      final words = _words(10);

      final first = await flow.openModule(
        ReviewModule.listeningMeaning,
        allWords: words,
        dailyGoal: 4,
      );
      // 用户把每日复习从 4 改成 6：词库补足，旧局的单词已经代表不了今天的任务。
      final afterChange = await flow.openModule(
        ReviewModule.listeningMeaning,
        allWords: words,
        dailyGoal: 6,
      );

      expect(afterChange!.session.id, isNot(first!.session.id));
      expect(afterChange.session.wordIds, <int>[1, 2, 3, 4, 5, 6]);
      // 旧局被收成「中断」，不会永远挂在数据库里。
      final old = sessionStore.sessions.firstWhere(
        (item) => item.id == first.session.id,
      );
      expect(old.status, ReviewSessionStatus.aborted);
    });

    test('会话里的单词被删除后，这一局作废并重开', () async {
      final wordSetStore = MemoryDailyWordSetStore();
      final sessionStore = MemoryReviewSessionStore();
      final flow = _flow(wordSetStore, sessionStore);

      final first = await flow.openModule(
        ReviewModule.listeningMeaning,
        allWords: _words(10),
        dailyGoal: 4,
      );
      // 删掉正在做的 2 号词。
      final remaining = <Word>[
        for (final word in _words(10))
          if (word.id != 2) word,
      ];
      final reopened = await flow.openModule(
        ReviewModule.listeningMeaning,
        allWords: remaining,
        dailyGoal: 4,
      );

      expect(reopened!.session.id, isNot(first!.session.id));
      expect(reopened.session.wordIds, isNot(contains(2)));
      expect(reopened.session.wordIds, hasLength(4));
    });

    test('四个模块共用同一份词库，各自的会话互不影响', () async {
      final wordSetStore = MemoryDailyWordSetStore();
      final sessionStore = MemoryReviewSessionStore();
      final flow = _flow(wordSetStore, sessionStore);
      final words = _words(10);

      final listening = await flow.openModule(
        ReviewModule.listeningMeaning,
        allWords: words,
        dailyGoal: 4,
      );
      final matching = await flow.openModule(
        ReviewModule.meaningMatch,
        allWords: words,
        dailyGoal: 4,
      );

      // 同一批词、同一个顺序。
      expect(listening!.session.wordIds, matching!.session.wordIds);
      expect(listening.session.wordSetId, matching.session.wordSetId);
      // 但是两局独立，各自都还在进行中。
      expect(listening.session.id, isNot(matching.session.id));
      expect(listening.session.status, ReviewSessionStatus.active);
      expect(matching.session.status, ReviewSessionStatus.active);
      // 词库只建了一次。
      expect(wordSetStore.saveCount, 1);
    });

    test('首页三态：没开过局是待完成，开着是进行中，过关是已完成', () async {
      final wordSetStore = MemoryDailyWordSetStore();
      final sessionStore = MemoryReviewSessionStore();
      final flow = _flow(wordSetStore, sessionStore);
      final words = _words(10);

      // 今天还没点开过任何模块。
      expect(await sessionStore.getTodayStates(), isEmpty);

      final entry = await flow.openModule(
        ReviewModule.listeningMeaning,
        allWords: words,
        dailyGoal: 4,
      );
      var states = await sessionStore.getTodayStates();
      expect(
        states[ReviewModule.listeningMeaning]!.progress,
        ReviewModuleProgress.active,
      );

      await sessionStore.finish(
        sessionId: entry!.session.id,
        status: ReviewSessionStatus.completed,
        wrongTotal: 0,
      );
      states = await sessionStore.getTodayStates();
      expect(
        states[ReviewModule.listeningMeaning]!.progress,
        ReviewModuleProgress.completed,
      );
      // 还没开始加练，尾巴不显示。
      expect(states[ReviewModule.listeningMeaning]!.isReinforcing, isFalse);

      // 过关后再进模块开一局巩固，卡片仍显示已完成，并补出「巩固中」。
      await flow.openModule(
        ReviewModule.listeningMeaning,
        allWords: words,
        dailyGoal: 4,
      );
      states = await sessionStore.getTodayStates();
      expect(
        states[ReviewModule.listeningMeaning]!.progress,
        ReviewModuleProgress.completed,
      );
      expect(states[ReviewModule.listeningMeaning]!.isReinforcing, isTrue);
    });

    test('失败的局不会让首页显示已完成', () async {
      final wordSetStore = MemoryDailyWordSetStore();
      final sessionStore = MemoryReviewSessionStore();
      final flow = _flow(wordSetStore, sessionStore);

      final entry = await flow.openModule(
        ReviewModule.listeningMeaning,
        allWords: _words(10),
        dailyGoal: 4,
      );
      await sessionStore.finish(
        sessionId: entry!.session.id,
        status: ReviewSessionStatus.failed,
        wrongTotal: 3,
      );

      final states = await sessionStore.getTodayStates();
      expect(
        states[ReviewModule.listeningMeaning]!.progress,
        ReviewModuleProgress.pending,
      );
    });

    test('词库为空时开不了局', () async {
      final wordSetStore = MemoryDailyWordSetStore();
      final sessionStore = MemoryReviewSessionStore();
      final flow = _flow(wordSetStore, sessionStore);

      final entry = await flow.openModule(
        ReviewModule.listeningMeaning,
        allWords: const <Word>[],
        dailyGoal: 4,
      );
      expect(entry, isNull);
      expect(sessionStore.sessions, isEmpty);
    });
  });

  group('跨天清理', () {
    test('昨天没打完的局在启动时被收成中断，今天的局不受影响', () async {
      final sessionStore = MemoryReviewSessionStore(today: '2026-08-23');
      // 手动塞一条昨天的进行中会话。
      sessionStore.sessions.add(
        ReviewSession(
          id: 99,
          module: ReviewModule.listeningMeaning,
          kind: ReviewSessionKind.daily,
          status: ReviewSessionStatus.active,
          wordSetId: 1,
          wordIds: const <int>[1, 2],
          state: const <String, Object?>{},
          wrongTotal: 0,
          sessionDate: '2026-08-22',
        ),
      );
      final today = await sessionStore.create(
        module: ReviewModule.meaningMatch,
        kind: ReviewSessionKind.daily,
        wordSetId: 1,
        wordIds: const <int>[1, 2],
      );

      final aborted = await sessionStore.abortActive(onlyStale: true);

      expect(aborted, 1);
      expect(
        sessionStore.sessions.firstWhere((item) => item.id == 99).status,
        ReviewSessionStatus.aborted,
      );
      // 今天的局完好无损。
      expect(
        sessionStore.sessions.firstWhere((item) => item.id == today.id).status,
        ReviewSessionStatus.active,
      );
    });
  });
}
