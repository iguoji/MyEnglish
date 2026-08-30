// material.dart 提供 MaterialApp / InkWell / Container 等控件，用于检查按钮状态。
import 'package:flutter/material.dart';
// flutter_test 提供 WidgetTester 与断言工具，用于驱动页面交互。
import 'package:flutter_test/flutter_test.dart';

// 被测页面、进度出口与依赖模型。
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/session.dart';
import 'package:my_english/models/session_record.dart';
import 'package:my_english/models/word.dart';
import 'package:my_english/pages/meaning_word_choice/meaning_word_choice_page.dart';
import 'package:my_english/pages/review/services/session_progress.dart';
import 'package:my_english/services/word_audio.dart';
import 'package:my_english/store/settings.dart';

// 测试用内存会话 Store，避免触碰 MethodChannel。
import '../../support/memory_session_store.dart';

///
/// 构造一个带唯一含义主键的单词。
///
/// [id] 单词主键；[meaningId] 该释义在 SQLite 里的主键（看义选词按它出题）。
///
Word _word(int id, int meaningId, String spelling, String definition, {String pos = 'n.'}) =>
    Word(
      id: id,
      spelling: spelling,
      meanings: <Meaning>[Meaning(id: meaningId, pos: pos, definition: definition)],
    );

///
/// 主词表：群落、战争、苹果三道题，另配两个干扰词。
///
/// 干扰词数量足够，保证每轮候选都能凑满四个。
///
List<Word> _fiveWords() => <Word>[
  _word(1, 101, 'community', '群落'),
  _word(2, 102, 'war', '战争'),
  _word(3, 103, 'apple', '苹果'),
  _word(4, 104, 'banana', '香蕉'),
  _word(5, 105, 'cat', '猫'),
];

///
/// 三词词表：苹果、香蕉两道题 + 一个干扰词。
///
List<Word> _threeWords() => <Word>[
  _word(3, 103, 'apple', '苹果'),
  _word(4, 104, 'banana', '香蕉'),
  _word(5, 105, 'cat', '猫'),
];

///
/// 多匹配词词表：eat 与 feed 共享「吃」这一道题，再加一道「苹果」。
///
List<Word> _eatWords() => <Word>[
  _word(1, 201, 'eat', '吃', pos: 'v.'),
  _word(2, 202, 'feed', '吃', pos: 'v.'),
  _word(3, 203, 'apple', '苹果'),
];

///
/// 构造一局「进行中」的看义选词会话。
///
/// [items] 是含义主键列表（答题顺序）；[cursor] / [elapsed] 来自上次保存的进度。
///
Session _session({required List<int> items, int cursor = 0, int elapsed = 0}) => Session(
  id: 1,
  module: ReviewModule.meaningWordChoice,
  kind: SessionKind.daily,
  status: SessionStatus.active,
  wordSetId: 1,
  items: items,
  cursor: cursor,
  elapsed: elapsed,
  date: '2026-08-29',
  createdAt: DateTime.now(),
);

///
/// 音频测试替身：只实现 play / stop，其余媒体控制方法用默认空实现。
///
/// 必须用 extends 而不是 implements——WordAudioPlayer 是带默认实现的抽象类，
/// implements 会强制重写全部成员，extends 才能复用空实现。
///
class _SilentAudioPlayer extends WordAudioPlayer {
  @override
  Future<void> play(String spelling, PronunciationAccent accent) async {}

  @override
  Future<void> stop() async {}
}

///
/// 把页面装进 MaterialApp 并完成首帧。
///
Future<void> _pumpPage(
  WidgetTester tester, {
  required List<Word> words,
  required SessionProgress progress,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MeaningWordChoicePage(
        words: words,
        title: '看义选词',
        progress: progress,
        audioPlayer: _SilentAudioPlayer(),
        accent: PronunciationAccent.american,
      ),
    ),
  );
  // 多跑一帧让 initState 的恢复逻辑与滚动回调全部落地。
  await tester.pump();
}

///
/// 取出候选区全部按钮的 key（如 `meaning-word-choice-option-3`）。
///
/// 候选词由服务按字母升序生成，但「选哪几个干扰词」是随机的，所以测试
/// 不假设某个词固定在第几个按钮，而是先列出全部按钮再按主键找目标。
///
List<String> _candidateKeys(WidgetTester tester) => tester
    .widgetList<Container>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'meaning-word-choice-option-',
            ),
      ),
    )
    .map((container) => (container.key! as ValueKey<String>).value)
    .toList();

///
/// 取出某个候选按钮的 InkWell，检查它是否还允许点击。
///
/// 候选按钮的 key 挂在按钮本体 Container 上，InkWell 是它的**父级**包裹层，
/// 所以要沿祖先链向上找，而不是找后代。
///
InkWell _inkWellOf(WidgetTester tester, String key) => tester.widget<InkWell>(
  find.ancestor(of: find.byKey(Key(key)), matching: find.byType(InkWell)),
);

void main() {
  testWidgets('新局：先三点动画再出含义，答对进入下一题，答错候选置灰', (WidgetTester tester) async {
    final store = MemorySessionStore();
    final progress = SessionProgress(
      store: store,
      session: _session(items: <int>[103, 104]),
      records: const <SessionRecord>[],
    );
    await _pumpPage(tester, words: _threeWords(), progress: progress);

    // 第一帧还在「正在输入」动画中，含义气泡还没出。
    expect(find.text('苹果'), findsNothing);
    // 900ms 假输入结束后含义气泡出现。
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('苹果'), findsOneWidget);

    // 点错一个非匹配候选：按钮置灰不可再点，并记一条答错。
    final wrongKey = _candidateKeys(tester).firstWhere(
      (key) => key != 'meaning-word-choice-option-3',
    );
    await tester.tap(find.byKey(Key(wrongKey)));
    await tester.pump();
    expect(_inkWellOf(tester, wrongKey).onTap, isNull);
    expect(store.recordWrites.where((write) => !write.isCorrect), hasLength(1));

    // 点对 apple：选中即直接弹出单词气泡并进入下一题（正确词不再有右侧三点动画）。
    await tester.tap(find.text('apple'));
    await tester.pump();
    // 下一轮开局的「正在输入」假输入结束，「香蕉」气泡出现。
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(const Key('meaning-word-choice-bubble-word-3')), findsOneWidget);
    expect(find.text('香蕉'), findsOneWidget);
    // 记了一条答对记录，且 apple 被结算。
    expect(store.recordWrites.where((write) => write.isCorrect), hasLength(1));
    expect(store.settles.where((settle) => settle.wordId == 3), hasLength(1));

    // 卸载页面，让计时器全部清理，避免测试结束时挂起。
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('续玩：历史气泡随消息一起重建，当前轮含义只出现一次', (WidgetTester tester) async {
    // 用户此前答对了「群落」和「战争」，退出时停在「苹果」这题。
    final store = MemorySessionStore();
    final progress = SessionProgress(
      store: store,
      session: _session(items: <int>[101, 102, 103], cursor: 2, elapsed: 5),
      records: const <SessionRecord>[
        SessionRecord(id: 1, wordId: 1, meaningId: 101, input: 'community', isCorrect: true),
        SessionRecord(id: 2, wordId: 2, meaningId: 102, input: 'war', isCorrect: true),
      ],
    );
    await _pumpPage(tester, words: _fiveWords(), progress: progress);

    // 历史两轮的气泡完整重建：含义 + 答对的单词。
    expect(find.text('群落'), findsOneWidget);
    expect(find.text('战争'), findsOneWidget);
    expect(find.byKey(const Key('meaning-word-choice-bubble-word-1')), findsOneWidget);
    expect(find.byKey(const Key('meaning-word-choice-bubble-word-2')), findsOneWidget);
    // 顶栏显示第 3 题。
    expect(find.text('3 / 3'), findsOneWidget);

    // 当前轮「苹果」的含义气泡只出现一次——修复前它会先随历史一起重建，
    // 再在「正在输入」动画结束后被多插一次。
    expect(find.text('苹果'), findsOneWidget);
    // 等一个完整的假输入周期，确认没有第二个气泡冒出来。
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('苹果'), findsOneWidget);
    // 续玩恢复不播放「正在输入」动画，含义气泡是立即出现的。

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('续玩：多匹配词轮只答对一个，重进后不误判完成并恢复已选词', (WidgetTester tester) async {
    // 「吃」同时匹配 eat 与 feed，用户只答对了 eat 就退出。
    final store = MemorySessionStore();
    final progress = SessionProgress(
      store: store,
      session: _session(items: <int>[201, 203], cursor: 0, elapsed: 3),
      records: const <SessionRecord>[
        SessionRecord(id: 1, wordId: 1, meaningId: 201, input: 'eat', isCorrect: true),
      ],
    );
    await _pumpPage(tester, words: _eatWords(), progress: progress);

    // 仍在第 1 题「吃」——修复前会把这道多匹配词轮误判成已完成，直接跳到苹果。
    expect(find.text('1 / 2'), findsOneWidget);
    // 当前轮含义气泡「吃」只出现一次。
    expect(find.text('吃'), findsOneWidget);
    // 已答对的 eat 恢复成聊天区气泡，候选区按钮恢复绿色禁用态（不可再点）。
    expect(find.byKey(const Key('meaning-word-choice-bubble-word-1')), findsOneWidget);
    expect(_inkWellOf(tester, 'meaning-word-choice-option-1').onTap, isNull);

    // 补答 feed：本轮两个匹配词都选出后进入「苹果」轮。
    await tester.tap(find.byKey(const Key('meaning-word-choice-option-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('苹果'), findsOneWidget);
    // eat 与 feed 都在这一轮被结算。
    expect(store.settles.map((settle) => settle.wordId).toSet(), containsAll(<int>{1, 2}));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('续玩：当前轮点错的候选恢复置灰，补答后正常推进', (WidgetTester tester) async {
    // 用户在「吃」这轮点错过 apple（干扰词），随后退出。
    final store = MemorySessionStore();
    final progress = SessionProgress(
      store: store,
      session: _session(items: <int>[201, 203], cursor: 0, elapsed: 2),
      records: const <SessionRecord>[
        SessionRecord(id: 1, wordId: 3, meaningId: 201, input: 'apple', isCorrect: false),
      ],
    );
    await _pumpPage(tester, words: _eatWords(), progress: progress);

    // 当前轮仍是「吃」，点错过的 apple 恢复置灰。
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('吃'), findsOneWidget);
    expect(_inkWellOf(tester, 'meaning-word-choice-option-3').onTap, isNull);

    // 把 eat、feed 都补上，本轮完成进入「苹果」。
    await tester.tap(find.byKey(const Key('meaning-word-choice-option-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(find.byKey(const Key('meaning-word-choice-option-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('苹果'), findsOneWidget);
    // 本次补答只新增了两条答对记录（eat、feed），没有新的点错写入；
    // 历史那次点错只影响现场恢复，不重复记账。
    expect(store.recordWrites, hasLength(2));
    expect(store.recordWrites.where((write) => write.isCorrect), hasLength(2));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('全部答完进入结算页：一次选对 2、失误 0、会话收尾为已完成', (WidgetTester tester) async {
    final store = MemorySessionStore();
    final progress = SessionProgress(
      store: store,
      session: _session(items: <int>[103, 104]),
      records: const <SessionRecord>[],
    );
    await _pumpPage(tester, words: _threeWords(), progress: progress);

    // 第一题：苹果。
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(find.text('apple'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    // 第二题：香蕉。
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(find.text('banana'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    // 两题全部答完，进入结算页。
    expect(find.text('看义选词完成'), findsOneWidget);
    // 一次选对 = 2（两轮都没点错），失误 = 0。
    expect(
      find.descendant(
        of: find.byKey(const Key('meaning-word-choice-stat-perfect')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('meaning-word-choice-stat-errors')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
    // 会话被判定为已完成。
    expect(store.finishes, hasLength(1));
    expect(store.finishes.single.status, SessionStatus.completed);

    await tester.pumpWidget(const SizedBox());
  });
}
