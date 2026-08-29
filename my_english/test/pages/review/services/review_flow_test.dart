import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_english/models/session.dart';
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';
import 'package:my_english/pages/review/services/review_flow.dart';

// 测试用内存实现：词表 Store（含两层选词排序）与会话 Store（有状态）。
import '../../../support/memory_word_store.dart';
import '../../../support/memory_session_store.dart';

///
/// 构造一个可入库的测试单词。
Word _word(int id, {DateTime? reviewedAt}) => Word(
  id: id,
  // 拼写按编号补零，保证「拼写升序」与「编号升序」结论一致，断言更直观。
  spelling: 'w${id.toString().padLeft(3, '0')}',
  meanings: <Meaning>[
    Meaning(id: id * 100, pos: 'n.', definition: '释义'),
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
  MemoryWordStore wordStore,
  MemorySessionStore sessionStore,
) => ReviewFlow(
  wordStore: wordStore,
  sessionStore: sessionStore,
  random: Random(2026),
);

///
/// 验证「创建词库」与「创建会话」两条核心流程（v2.0 会话模型）。
void main() {
  const date = '2026-08-23';

  group('创建词库', () {
    test('今天第一次进模块时按两层规则选出目标数量并落库', () async {
      final wordStore = MemoryWordStore(_words(10));
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      final wordSet = await flow.resolveWordSet(
        dailyGoal: 4,
        libraryCount: 10,
        date: date,
      );

      expect(wordSet, isNotNull);
      // 第一层（难词）2 个 + 第二层（久未复习）2 个 = 1..4。
      expect(wordSet!.todayWordIds, <int>[1, 2, 3, 4]);
      expect(wordSet.wordCount, 4);
      // 明天的词 = 排除今天后最前面的一半（向上取整 2 个）。
      expect(wordSet.tomorrowWordIds, <int>[5, 6]);
      // 词库只建了一次。
      expect(sessionStore.wordSets, hasLength(1));
    });

    test('目标没变时直接复用今天的词库，不做多余写入', () async {
      final wordStore = MemoryWordStore(_words(10));
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      await flow.resolveWordSet(dailyGoal: 4, libraryCount: 10, date: date);
      final second = await flow.resolveWordSet(
        dailyGoal: 4,
        libraryCount: 10,
        date: date,
      );

      expect(second!.todayWordIds, <int>[1, 2, 3, 4]);
      // 第二次完全复用，没有再写一遍数据库。
      expect(sessionStore.wordSets, hasLength(1));
    });

    test('目标调小时从前面截取', () async {
      final wordStore = MemoryWordStore(_words(10));
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      await flow.resolveWordSet(dailyGoal: 5, libraryCount: 10, date: date);
      final shrunk = await flow.resolveWordSet(
        dailyGoal: 2,
        libraryCount: 10,
        date: date,
      );

      expect(shrunk!.todayWordIds, <int>[1, 2]);
    });

    test('目标调大时排除已有单词再补足，绝不补出重复', () async {
      final wordStore = MemoryWordStore(_words(10));
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      // 先按目标 3 建库，拿到 1、2、3。
      await flow.resolveWordSet(dailyGoal: 3, libraryCount: 10, date: date);

      // 关键场景：已经练过的 1、2、3 复习时间被推进，掉到排序最后面。
      // 如果补词时不排除已有 id，从头拉 2 个会拉回 4、5 之外的错误结果。
      final now = DateTime(2026, 8, 23, 12);
      wordStore.words
        ..clear()
        ..addAll(<Word>[
          _word(1, reviewedAt: now),
          _word(2, reviewedAt: now),
          _word(3, reviewedAt: now),
          for (var id = 4; id <= 10; id += 1) _word(id),
        ]);
      final grown = await flow.resolveWordSet(
        dailyGoal: 5,
        libraryCount: 10,
        date: date,
      );

      // 原有三个保持原顺序，末尾补上两个全新的。
      expect(grown!.todayWordIds, <int>[1, 2, 3, 4, 5]);
      // 没有任何单词出现两次。
      expect(grown.todayWordIds.toSet().length, grown.todayWordIds.length);
    });

    test('词库里的单词被删除后，剔除失效主键并从排序结果补足', () async {
      final wordStore = MemoryWordStore(_words(10));
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      await flow.resolveWordSet(dailyGoal: 4, libraryCount: 10, date: date);
      // 删掉 2 号：剩下 1、3、4，再从排序结果补一个 5。
      await wordStore.delete(2);
      final repaired = await flow.resolveWordSet(
        dailyGoal: 4,
        libraryCount: 9,
        date: date,
      );

      expect(repaired!.todayWordIds, <int>[1, 3, 4, 5]);
    });

    test('词库总量不足目标时以实际数量为准，不反复重写', () async {
      final wordStore = MemoryWordStore(_words(3));
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      // 只录了 3 个词，目标却设成 50。
      final first = await flow.resolveWordSet(
        dailyGoal: 50,
        libraryCount: 3,
        date: date,
      );
      final second = await flow.resolveWordSet(
        dailyGoal: 50,
        libraryCount: 3,
        date: date,
      );

      expect(first!.todayWordIds, <int>[1, 2, 3]);
      expect(second!.todayWordIds, <int>[1, 2, 3]);
      // 第二次没有再写一遍——这正是「目标取实际数量」要解决的浪费。
      expect(sessionStore.wordSets, hasLength(1));
    });

    test('词库为空或目标为 0 时拿不到词库', () async {
      final wordStore = MemoryWordStore(<Word>[]);
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      expect(
        await flow.resolveWordSet(dailyGoal: 5, libraryCount: 0, date: date),
        isNull,
      );
      expect(
        await flow.resolveWordSet(dailyGoal: 0, libraryCount: 5, date: date),
        isNull,
      );
    });
  });

  group('创建会话', () {
    test('今天第一次进模块开一局主线，单词就是整份词库', () async {
      final wordStore = MemoryWordStore(_words(10));
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      final entry = await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 4,
        libraryCount: 10,
        date: date,
      );

      expect(entry, isNotNull);
      expect(entry!.session.kind, SessionKind.daily);
      expect(entry.session.status, SessionStatus.active);
      // 听音辨义的数据列表就是单词主键。
      expect(entry.session.idItems, <int>[1, 2, 3, 4]);
      // 主线会话答题要推进复习时间。
      expect(entry.session.updatesReviewedAt, isTrue);
      // 返回的单词与会话顺序严格一致。
      expect(entry.words.keys.toList(), <int>[1, 2, 3, 4]);
      // 全新一局没有任何记录。
      expect(entry.isFresh, isTrue);
    });

    test('已有进行中的局直接续上，不会重开', () async {
      final wordStore = MemoryWordStore(_words(10));
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      final first = await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 4,
        libraryCount: 10,
        date: date,
      );
      // 模拟用户做到一半退出去，进度已经落盘。
      await sessionStore.updateProgress(
        sessionId: first!.session.id,
        cursor: 2,
        elapsed: 5,
      );
      final resumed = await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 4,
        libraryCount: 10,
        date: date,
      );

      expect(resumed!.session.id, first.session.id);
      // 续上的这一局带着上次的进度。
      expect(resumed.session.cursor, 2);
      expect(resumed.session.elapsed, 5);
      expect(sessionStore.sessions, hasLength(1));
    });

    test('上一局失败后再进模块，重开一局主线而不是巩固', () async {
      final wordStore = MemoryWordStore(_words(10));
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      final first = await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 4,
        libraryCount: 10,
        date: date,
      );
      // 整局跑完但错过 → 失败。
      await sessionStore.finishSession(
        sessionId: first!.session.id,
        status: SessionStatus.failed,
      );
      final retry = await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 4,
        libraryCount: 10,
        date: date,
      );

      expect(retry!.session.id, isNot(first.session.id));
      expect(retry.session.kind, SessionKind.daily);
      // 重来的还是今天这批词，从头再走一遍。
      expect(retry.session.idItems, <int>[1, 2, 3, 4]);
    });

    test('主线过关后再进模块，开一局巩固：今天一半 + 明天一半', () async {
      final wordStore = MemoryWordStore(_words(20));
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      final daily = await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 4,
        libraryCount: 20,
        date: date,
      );
      // 整局跑完且一次没错 → 完成。
      await sessionStore.finishSession(
        sessionId: daily!.session.id,
        status: SessionStatus.completed,
      );

      // 主线过关后今天这 4 个词的复习时间已被推进，掉到排序最后面。
      final now = DateTime(2026, 8, 23, 12);
      wordStore.words
        ..clear()
        ..addAll(<Word>[
          for (final word in _words(20))
            if (word.id! <= 4) _word(word.id!, reviewedAt: now) else word,
        ]);
      final reinforce = await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 4,
        libraryCount: 20,
        date: date,
      );

      expect(reinforce!.session.kind, SessionKind.reinforce);
      // 巩固局不推进复习时间，明天这批词才不会被提前消耗掉。
      expect(reinforce.session.updatesReviewedAt, isFalse);
      // 题量不缩水：今天随机一半（2 个）+ 明天 2 个。
      expect(reinforce.session.idItems, hasLength(4));
      // 一半来自今天（1..4），一半来自明天（5..8）。
      final todayIds = <int>{1, 2, 3, 4};
      final fromToday = reinforce.session.idItems.where(todayIds.contains);
      expect(fromToday, hasLength(2));
      expect(reinforce.session.idItems.where((id) => id > 4), hasLength(2));
      // 同一局里不会出现重复单词。
      expect(
        reinforce.session.idItems.toSet().length,
        reinforce.session.idItems.length,
      );
    });

    test('词库总量不足两倍目标时，明天的词有多少拿多少，不用今天的补足', () async {
      final wordStore = MemoryWordStore(_words(5));
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      // 只有 5 个词、目标 4：明天最多只能凑出 1 个。
      final daily = await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 4,
        libraryCount: 5,
        date: date,
      );
      await sessionStore.finishSession(
        sessionId: daily!.session.id,
        status: SessionStatus.completed,
      );
      final reinforce = await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 4,
        libraryCount: 5,
        date: date,
      );

      // 今天固定随机拿一半 ceil(4×0.5)=2；明天只剩 1 个可选，就只拿 1 个。
      // 题量因此是 3 而不是 4——明天不够时不拿今天的来补。
      expect(reinforce!.session.idItems, hasLength(3));
      expect(
        reinforce.session.idItems.toSet().length,
        reinforce.session.idItems.length,
      );
    });

    test('每日复习量改了以后，旧的进行中主线会被中断并重开', () async {
      final wordStore = MemoryWordStore(_words(10));
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      final first = await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 4,
        libraryCount: 10,
        date: date,
      );
      // 用户把每日复习从 4 改成 6：词库补足，旧局的单词已经代表不了今天的任务。
      final afterChange = await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 6,
        libraryCount: 10,
        date: date,
      );

      expect(afterChange!.session.id, isNot(first!.session.id));
      expect(afterChange.session.idItems, <int>[1, 2, 3, 4, 5, 6]);
      // 旧局被收成「中断」，不会永远挂在数据库里。
      final old = sessionStore.sessions.firstWhere(
        (item) => item.id == first.session.id,
      );
      expect(old.status, SessionStatus.aborted);
    });

    test('会话里的单词被删除后，这一局作废并重开', () async {
      final wordStore = MemoryWordStore(_words(10));
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      final first = await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 4,
        libraryCount: 10,
        date: date,
      );
      // 删掉正在做的 2 号词。
      await wordStore.delete(2);
      final reopened = await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 4,
        libraryCount: 9,
        date: date,
      );

      expect(reopened!.session.id, isNot(first!.session.id));
      expect(reopened.session.idItems, isNot(contains(2)));
      expect(reopened.session.idItems, hasLength(4));
    });

    test('四个模块共用同一份词库，各自的会话互不影响', () async {
      final wordStore = MemoryWordStore(_words(10));
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      final listening = await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 4,
        libraryCount: 10,
        date: date,
      );
      final matching = await flow.openModule(
        ReviewModule.meaningMatch,
        dailyGoal: 4,
        libraryCount: 10,
        date: date,
      );

      // 同一批词、同一个顺序。词义连连的棋盘固定 5 张一组，词库只有 4 个词
      // 时会从前面随机补位一张到末组，因此只比较前 4 个。
      expect(
        matching!.session.pairItems.take(4).map((pair) => pair.wordId).toList(),
        listening!.session.idItems,
      );
      expect(listening.session.wordSetId, matching.session.wordSetId);
      // 补位后的棋盘仍是完整一组 5 张。
      expect(matching.session.pairItems, hasLength(5));
      // 但是两局独立，各自都还在进行中。
      expect(listening.session.id, isNot(matching.session.id));
      expect(listening.session.status, SessionStatus.active);
      expect(matching.session.status, SessionStatus.active);
      // 词库只建了一次。
      expect(sessionStore.wordSets, hasLength(1));
    });

    test('首页三态：没开过局是待完成，开着是进行中，过关是已完成', () async {
      final wordStore = MemoryWordStore(_words(10));
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      // 今天还没点开过任何模块。
      expect(await sessionStore.getTodayModuleStates(date), isEmpty);

      final entry = await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 4,
        libraryCount: 10,
        date: date,
      );
      var states = await sessionStore.getTodayModuleStates(date);
      expect(
        states[ReviewModule.listeningMeaning]!.progress,
        ReviewModuleProgress.active,
      );

      await sessionStore.finishSession(
        sessionId: entry!.session.id,
        status: SessionStatus.completed,
      );
      states = await sessionStore.getTodayModuleStates(date);
      expect(
        states[ReviewModule.listeningMeaning]!.progress,
        ReviewModuleProgress.completed,
      );
      // 还没开始加练，尾巴不显示。
      expect(states[ReviewModule.listeningMeaning]!.isReinforcing, isFalse);

      // 过关后再进模块开一局巩固，卡片仍显示已完成，并补出「巩固中」。
      await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 4,
        libraryCount: 10,
        date: date,
      );
      states = await sessionStore.getTodayModuleStates(date);
      expect(
        states[ReviewModule.listeningMeaning]!.progress,
        ReviewModuleProgress.completed,
      );
      expect(states[ReviewModule.listeningMeaning]!.isReinforcing, isTrue);
    });

    test('失败的局不会让首页显示已完成', () async {
      final wordStore = MemoryWordStore(_words(10));
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      final entry = await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 4,
        libraryCount: 10,
        date: date,
      );
      await sessionStore.finishSession(
        sessionId: entry!.session.id,
        status: SessionStatus.failed,
      );

      final states = await sessionStore.getTodayModuleStates(date);
      expect(
        states[ReviewModule.listeningMeaning]!.progress,
        ReviewModuleProgress.pending,
      );
    });

    test('词库为空时开不了局', () async {
      final wordStore = MemoryWordStore(<Word>[]);
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      final entry = await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 4,
        libraryCount: 0,
        date: date,
      );
      expect(entry, isNull);
      expect(sessionStore.sessions, isEmpty);
    });

    test('看义选词的数据列表是去重后的含义主键', () async {
      // eat 与 feed 共享「吃」，apple 有「苹果」。
      final wordStore = MemoryWordStore(<Word>[
        Word(
          id: 1,
          spelling: 'eat',
          meanings: <Meaning>[Meaning(id: 101, pos: 'v.', definition: '吃')],
        ),
        Word(
          id: 2,
          spelling: 'feed',
          meanings: <Meaning>[Meaning(id: 102, pos: 'v.', definition: '吃')],
        ),
        Word(
          id: 3,
          spelling: 'apple',
          meanings: <Meaning>[Meaning(id: 103, pos: 'n.', definition: '苹果')],
        ),
      ]);
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      final entry = await flow.openModule(
        ReviewModule.meaningWordChoice,
        dailyGoal: 3,
        libraryCount: 3,
        date: date,
      );

      // 含义主键按释义文本去重：两个「吃」只出一道题，总共 2 道。
      expect(entry!.session.idItems.toSet(), <int>{101, 103});
      expect(entry.session.idItems, hasLength(2));
    });
  });

  group('跨天清理', () {
    test('昨天没打完的局在启动时被收成中断，今天的局不受影响', () async {
      final sessionStore = MemorySessionStore(today: date);
      // 手动塞一条昨天的进行中会话。
      sessionStore.sessions.add(
        Session(
          id: 99,
          module: ReviewModule.listeningMeaning,
          kind: SessionKind.daily,
          status: SessionStatus.active,
          wordSetId: 1,
          items: const <int>[1, 2],
          cursor: 0,
          elapsed: 0,
          date: '2026-08-22',
        ),
      );
      final todayId = await sessionStore.createSession(
        module: ReviewModule.meaningMatch,
        kind: SessionKind.daily,
        wordSetId: 1,
        items: const <int>[1, 2],
        date: date,
      );

      final aborted = await sessionStore.abortStaleSessions(date);

      expect(aborted, 1);
      expect(
        sessionStore.sessions.firstWhere((item) => item.id == 99).status,
        SessionStatus.aborted,
      );
      // 今天的局完好无损。
      expect(
        sessionStore.sessions.firstWhere((item) => item.id == todayId).status,
        SessionStatus.active,
      );
    });
  });
}
