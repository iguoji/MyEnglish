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
  meanings: <Meaning>[Meaning(id: id * 100, pos: 'n.', definition: '释义')],
  reviewedAt: reviewedAt,
);

///
/// 生成 [count] 个从未复习过的单词，主键从 1 开始连续。
List<Word> _words(int count) => <Word>[
  for (var id = 1; id <= count; id += 1) _word(id),
];

///
/// 组装一个使用固定随机种子的复习流程，让巩固局抽词结果可复现。
///
/// 顺手把同一份词表挂给会话库：原生把「读计划 → 算配额 → 补缺选词」放在一个
/// SQLite 事务里，内存实现拆成两半，选词那半要问词表 Store 要。
///
ReviewFlow _flow(MemoryWordStore wordStore, MemorySessionStore sessionStore) {
  sessionStore.wordStore = wordStore;
  return ReviewFlow(
    wordStore: wordStore,
    sessionStore: sessionStore,
    random: Random(2026),
  );
}

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
      // 明天那份计划是**独立的一份**，按同一个目标数量去建，只是排除今天这批：
      // 所以拿到的是接下来的 4 个（5..8），不是今天的一半。第二天进来时它就是
      // 「明天的主线」，份量和今天一样。
      expect(wordSet.tomorrowWordIds, <int>[5, 6, 7, 8]);
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

    test('目标调小时按 40/60 分层配额削减，不会砍光久词', () async {
      final wordStore = MemoryWordStore(_words(10));
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      await flow.resolveWordSet(dailyGoal: 5, libraryCount: 10, date: date);
      final shrunk = await flow.resolveWordSet(
        dailyGoal: 2,
        libraryCount: 10,
        date: date,
      );

      // 目标 5 时计划是难词 1、2 + 久词 3、4、5。目标降到 2 时按 40/60 的配额
      // 各留一部分：难词留 ceil(2×0.4)=1 个（1），久词留 2-1=1 个（3）。
      // 如果直接按计划的写入顺序从头截断，留下的会是 1、2 两个难词、久词一个
      // 不剩——「每日复习 50 改回 15 就全是难词」正是这条规则要避免的。
      expect(shrunk!.todayWordIds, <int>[1, 3]);
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

    test('目标为 0 时连计划都不建；词库为空时计划建得出来但一个词都没有', () async {
      // 目标为 0：没有「今天要背什么」这回事，连计划行都不该建。
      final zeroGoalFlow = _flow(
        MemoryWordStore(<Word>[]),
        MemorySessionStore(today: date),
      );
      expect(
        await zeroGoalFlow.resolveWordSet(
          dailyGoal: 0,
          libraryCount: 5,
          date: date,
        ),
        isNull,
      );

      // 词库为空、目标却大于 0：计划本身会建出来（词库补上后继续用它），
      // 只是里面一个词都没有。**「开不了局」由开局流程按空计划判断**，
      // 不靠这里返回空——否则「先建库、后录词」的用户每次都要重建计划。
      final wordStore = MemoryWordStore(<Word>[]);
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);
      final plan = await flow.resolveWordSet(
        dailyGoal: 5,
        libraryCount: 0,
        date: date,
      );
      expect(plan, isNotNull);
      expect(plan!.todayWordIds, isEmpty);
      expect(plan.wordCount, 0);
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
      // 听音辨义的数据列表就是单词主键；主线题序会把前两层选出的难词按位置
      // 均匀铺开（4 个词、2 个难词 → 难词落在第 1、3 位），不让难词连成一串。
      expect(entry.session.idItems, <int>[1, 3, 2, 4]);
      // 主线会话答题要推进复习时间。
      expect(entry.session.updatesReviewedAt, isTrue);
      // 返回的单词与会话顺序严格一致。
      expect(entry.words.keys.toList(), <int>[1, 3, 2, 4]);
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
      // 重来的还是今天这批词，从头再走一遍；主线题序仍按均衡铺开的规则创建。
      expect(retry.session.idItems, <int>[1, 3, 2, 4]);
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

    test('明天的词不够时用今天剩余的补足，题量不缩水', () async {
      final wordStore = MemoryWordStore(_words(5));
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      // 只有 5 个词、目标 4：今天占掉 1..4，明天只剩 5 号这一个可选。
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

      // 先按各取一半：今天 ceil(4×0.5)=2 个、明天 4~/2=2 个。明天只有 1 个可选，
      // 缺的那 1 个再回今天剩余的里补，所以题量仍是 4、不会缩水。
      // 补的顺序是「先明天、后今天」——明天有货先用明天的，真不够才动今天的存货。
      expect(reinforce!.session.idItems, hasLength(4));
      expect(reinforce.session.idItems, contains(5));
      expect(reinforce.session.idItems.where((id) => id <= 4), hasLength(3));
      expect(
        reinforce.session.idItems.toSet().length,
        reinforce.session.idItems.length,
      );
    });

    test('每日复习量改了以后，计划按新目标补足，已开始的会话继续用快照', () async {
      final wordStore = MemoryWordStore(_words(10));
      final sessionStore = MemorySessionStore(today: date);
      final flow = _flow(wordStore, sessionStore);

      final first = await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 4,
        libraryCount: 10,
        date: date,
      );
      // 用户把每日复习从 4 改成 6。
      final afterChange = await flow.openModule(
        ReviewModule.listeningMeaning,
        dailyGoal: 6,
        libraryCount: 10,
        date: date,
      );

      // 已经开着的这一局原样续上：题目是开局那一刻的快照，中途改目标不该把
      // 用户正在做的题换掉，更不该把进度收成「中断」。
      expect(afterChange!.session.id, first!.session.id);
      expect(afterChange.session.idItems, first.session.idItems);
      expect(
        sessionStore.sessions
            .firstWhere((item) => item.id == first.session.id)
            .status,
        SessionStatus.active,
      );

      // 计划本身跟着新目标走。注意：**首页是走「刷新看板」那条路**去补计划的
      // （打开模块时若已有进行中的局会直接续上、不再算计划），所以这里显式
      // 取一次计划来验证补缺结果。
      final plan = await flow.resolveWordSet(
        dailyGoal: 6,
        libraryCount: 10,
        date: date,
      );
      expect(plan!.todayWordIds, <int>[1, 2, 3, 4, 5, 6]);
      expect(plan.tomorrowWordIds, <int>[7, 8, 9, 10]);
    });

    test('会话里的单词被删除后，计划下次取用时补缺，已开的局继续保留', () async {
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

      // 原生删词只软删单词本身，**不动已经开好的局**：题目、词库快照和答题
      // 进度都留着，所以这里续上的还是同一局，不会被凭空作废。
      expect(reopened!.session.id, first!.session.id);
      expect(reopened.session.idItems, first.session.idItems);

      // 计划在下次取用时补缺：2 号被剔除，从剩下的词里补一个 5 号。
      // 续上的那一局不会触发补缺（有进行中的局就直接返回了），所以这里显式取一次。
      final plan = await flow.resolveWordSet(
        dailyGoal: 4,
        libraryCount: 9,
        date: date,
      );
      expect(plan!.todayWordIds, <int>[1, 3, 4, 5]);
      expect(plan.todayWordIds, isNot(contains(2)));
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

      // 同一批词、同一个顺序。词义连连不再为凑满一组 5 张而补位：
      // 词库只有 4 个词时数据列表就是这 4 对，棋盘按实际张数铺开。
      expect(
        matching!.session.pairItems.map((pair) => pair.wordId).toList(),
        listening!.session.idItems,
      );
      expect(listening.session.wordSetId, matching.session.wordSetId);
      // 词太少不再被补成一组 5 张，有多少对就开多少对。
      expect(matching.session.pairItems, hasLength(4));
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

    test('看义选词按释义去重：两个「吃」只出一道题', () async {
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

      // 数据列表是**小题主键**的投影，只用来便宜地问一句「这一局有几题」；
      // 页面真正读的是试卷（groups）与词库快照。
      expect(entry!.session.idItems, hasLength(2));
      // 去重的证据在题干上：两道题分别是「吃」和「苹果」。两个「吃」
      // （eat / feed）合成一道多选题，不是各出一道。
      expect(
        <String>{
          for (final question in entry.session.questions) ...question.content,
        },
        <String>{'吃', '苹果'},
      );
      // 看义选词是「给中文选英文」，答案是拼写，所以答案类型是单词。
      expect(
        entry.session.questions.every((question) => question.answerType == 1),
        isTrue,
      );
    });
  });

  group('跨天清理', () {
    test('昨天一条答案都没答的局在启动时被中断，今天的局不受影响', () async {
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

      final closed = await sessionStore.settleStaleSessions(date);

      expect(closed, 1);
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
