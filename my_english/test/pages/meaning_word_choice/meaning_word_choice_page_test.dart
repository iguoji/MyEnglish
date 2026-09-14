// flutter_test 提供 WidgetTester 与断言工具，用于驱动页面交互。
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

// 引入设计令牌，核对候选卡状态样式。
import 'package:my_english/common/theme.dart';
// 被测页面与依赖模型。
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/session.dart';
import 'package:my_english/models/session_record.dart';
import 'package:my_english/models/word.dart';
import 'package:my_english/pages/meaning_word_choice/meaning_word_choice_page.dart';
import 'package:my_english/pages/meaning_word_choice/widgets/meaning_word_choice_layout.dart';
import 'package:my_english/pages/review/services/session_progress.dart';
import 'package:my_english/services/word_audio.dart';
import 'package:my_english/store/settings.dart';

// 测试用内存会话 Store，避免触碰 MethodChannel。
import '../../support/memory_session_store.dart';
// 测试用会话装配件：按真实规则编好试卷再组装会话。
import '../../support/session_fixture.dart';

///
/// 构造一个带唯一含义主键的单词。
///
/// [id] 单词主键；[meaningId] 该释义在 SQLite 里的主键（看义选词按它出题）。
///
Word _word(
  int id,
  int meaningId,
  String spelling,
  String definition, {
  String pos = 'n.',
}) => Word(
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
/// 三词词表：苹果、香蕉、猫三道题，另配两个干扰词。
///
List<Word> _threeWords() => <Word>[
  _word(3, 103, 'apple', '苹果'),
  _word(4, 104, 'banana', '香蕉'),
  _word(5, 105, 'cat', '猫'),
];

///
/// 多匹配词词表：eat 与 feed 共享「吃」这一道题。
///
/// 只留一道题，是为了让「这一轮还没答完」这个断言有唯一确定的落点：
/// 出题顺序由词库打乱，多道题时哪一道排在前面每次都不一样。
///
List<Word> _eatWords() => <Word>[
  _word(1, 201, 'eat', '吃', pos: 'v.'),
  _word(2, 202, 'feed', '吃', pos: 'v.'),
];

///
/// 按词表构造一局「进行中」的看义选词会话。
///
/// 一局练习在库里是**四层**（会话 → 大题 → 小题 → 考察对象），页面读的是
/// `session.groups` 里编好的试卷；数据列表（items）只是「这一局有几题」的
/// 便宜投影，单独填它会让页面拿到一份空试卷。所以这里调生产代码的编题规则。
///
/// [pinnedDistractors] 见 [buildPaper]：把某道题的候选钉死，用例才能断言
/// 「点错的那一项在第几号位」。
///
Session _session(
  List<Word> words, {
  int cursor = 0,
  int elapsed = 0,
  Map<String, List<String>>? pinnedDistractors,
}) => buildSession(
  id: 1,
  module: ReviewModule.meaningWordChoice,
  words: words,
  date: '2026-08-29',
  cursor: cursor,
  elapsed: elapsed,
  pinnedDistractors: pinnedDistractors,
);

///
/// 把会话包成页面需要的进度出口，并登记进内存 Store。
///
/// 会话必须出现在 Store 里：答题、保存进度、结算都按编号回查这一局。
///
({SessionProgress progress, MemorySessionStore store}) _progressFor(
  Session session, {
  required List<Word> words,
  List<SessionRecord> records = const <SessionRecord>[],
}) {
  final store = MemorySessionStore();
  store.seedSession(session);
  return (
    store: store,
    progress: SessionProgress(
      store: store,
      session: session,
      records: records,
      // 候选干扰项需要一份「全词库语料」。显式交进去，页面就不会去敲原生词库
      // 通道取词——那条通道在 Widget 测试里没有实现，候选会一直等不到结果，
      // 整页停在「候选加载中」，连四张卡都渲染不出来。
      corpusWords: words,
    ),
  );
}

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
/// 把页面装进 MaterialApp 并等候选就位。
///
Future<void> _pumpPage(
  WidgetTester tester, {
  required List<Word> words,
  required SessionProgress progress,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      // 必须装上真实主题：页面里的字号、字重、文字色统一从主题的 TextTheme
      // 槽位取，缺了它读到的会是 Material 自带的默认字号。
      theme: AppTheme.light,
      home: MeaningWordChoicePage(
        words: words,
        title: '看义选词',
        progress: progress,
        audioPlayer: _SilentAudioPlayer(),
        accent: PronunciationAccent.american,
      ),
    ),
  );
  // 候选是异步准备的（要写一次干扰项），必须等它落位再断言。
  await tester.pumpAndSettle();
}

///
/// 试卷里第 [index] 道题的释义文本。
///
/// 出题顺序由编题规则打乱，用例不假设「第一题一定是苹果」，而是从真实试卷
/// 里把当前这道题的释义与答案读出来。
///
String _definitionOf(Session session, int index) =>
    session.questions[index].content.first;

///
/// 试卷里第 [index] 道题的正确答案拼写（多匹配词轮会不止一个）。
///
List<String> _answersOf(Session session, int index) =>
    session.questions[index].answers;

///
/// 试卷里第 [index] 道题的小题编号；答题记录靠它和题目对上号。
///
int _questionIdOf(Session session, int index) => session.questions[index].id;

///
/// 按拼写反查单词主键。
///
int _idOf(List<Word> words, String spelling) =>
    words.firstWhere((word) => word.spelling == spelling).id!;

///
/// 造「前 [count] 道题已经全部答对」的历史点击记录。
///
List<SessionRecord> _completedRecords(Session session, int count) =>
    <SessionRecord>[
      for (var index = 0; index < count; index += 1)
        SessionRecord(
          id: index + 1,
          wordId: session.questions[index].details.first.wordId,
          meaningId: session.questions[index].details.first.meaningId,
          input: session.questions[index].answers.first,
          isCorrect: true,
          questionId: session.questions[index].id,
        ),
    ];

///
/// 按位置读取当前候选区显示的文字。
///
/// 候选卡（共用组件 `ChoiceOptionGrid`）把文字挂在内部 `FittedBox` 的 key 上，
/// key 就是文字本身；卡片本身的 key 只认「第几号位」，换题不会整块重建。
///
List<String> _candidateTexts(WidgetTester tester) {
  final texts = <String>[];
  for (var index = 0; index < 4; index += 1) {
    final card = find.byKey(Key('meaning-word-choice-option-$index'));
    if (!tester.any(card)) continue;
    final boxes = tester
        .widgetList<FittedBox>(
          find.descendant(of: card, matching: find.byType(FittedBox)),
        )
        .toList();
    // 换轮交叉淡入的一瞬间新旧两格同时在树里，取最后加入的那一个。
    final key = boxes.isEmpty ? null : boxes.last.key;
    if (key is ValueKey<String>) texts.add(key.value);
  }
  return texts;
}

///
/// 取出第 [index] 号位候选按钮的 InkWell，检查它是否还允许点击。
///
/// 候选按钮的 key 挂在卡片本体上，InkWell 在它**内部**包着卡面，
/// 所以要沿后代链向下找，而不是找祖先。
///
InkWell _inkWellOf(WidgetTester tester, int index) => tester.widget<InkWell>(
  find.descendant(
    of: find.byKey(Key('meaning-word-choice-option-$index')),
    matching: find.byType(InkWell),
  ),
);

///
/// 点一下文字为 [spelling] 的那张候选卡。
///
/// 不假设它固定在第几号位：候选按字母升序排，干扰词又是现算的。
///
Future<void> _tapCandidate(WidgetTester tester, String spelling) async {
  final index = _candidateTexts(tester).indexOf(spelling);
  expect(
    index,
    isNonNegative,
    reason: '候选里没有 $spelling：${_candidateTexts(tester)}',
  );
  // 换轮之后有 350 毫秒的点击保护期。它只是一段计时器、不安排新帧，
  // `pumpAndSettle` 走不到它结束，必须显式把时钟推过去再点。
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.byKey(Key('meaning-word-choice-option-$index')));
  await tester.pump();
}

///
/// 读出某个答案单词第 [index] 个字符那一格里显示的字母；空格返回 null。
///
/// 白卡版把答案画成「一个字母一条下划线」，所以断言要落到单格上，
/// 而不是找一整个单词的 Text。
///
String? _slotLetter(
  WidgetTester tester, {
  required int wordId,
  required int index,
}) {
  final finder = find.descendant(
    of: find.byKey(Key('meaning-word-choice-slot-$wordId-$index')),
    matching: find.byType(Text),
  );
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Text>(finder).data;
}

///
/// 本轮答完后到切题之间的停顿，与页面用的是同一个常量。
///
const Duration _advanceDelay = Duration(
  milliseconds: MeaningWordChoiceLayout.roundAdvanceDelayMs,
);

void main() {
  testWidgets('新局：白卡直接出释义，答对整词填入字母格再进入下一题', (WidgetTester tester) async {
    final words = _threeWords();
    final session = _session(words);
    final fixture = _progressFor(session, words: words);
    final store = fixture.store;
    await _pumpPage(tester, words: words, progress: fixture.progress);

    // 第一道题的释义与答案都从真实试卷里读。
    final firstDefinition = _definitionOf(session, 0);
    final firstAnswer = _answersOf(session, 0).single;
    final firstWordId = _idOf(words, firstAnswer);

    // 白卡与释义大字第一帧就在：白卡版没有「正在输入」这一段假动画。
    expect(
      find.byKey(const Key('meaning-word-choice-question-card')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('meaning-word-choice-tag')), findsOneWidget);
    expect(find.text(firstDefinition), findsOneWidget);
    // 答对之前字母格全是空的。
    expect(_slotLetter(tester, wordId: firstWordId, index: 0), isNull);

    // 点错一个非匹配候选：按钮置灰不可再点，并记一条答错。
    final candidates = _candidateTexts(tester);
    expect(candidates, hasLength(4));
    final wrongSpelling = candidates.firstWhere((text) => text != firstAnswer);
    final wrongIndex = candidates.indexOf(wrongSpelling);
    await _tapCandidate(tester, wrongSpelling);
    expect(_inkWellOf(tester, wrongIndex).onTap, isNull);
    expect(store.recordWrites.where((write) => !write.isCorrect), hasLength(1));

    // 点对正确拼写：整词一次填进字母格，题目还停在当前这一屏。
    await _tapCandidate(tester, firstAnswer);
    expect(_slotLetter(tester, wordId: firstWordId, index: 0), firstAnswer[0]);
    expect(
      _slotLetter(tester, wordId: firstWordId, index: firstAnswer.length - 1),
      firstAnswer[firstAnswer.length - 1],
    );
    expect(find.text(firstDefinition), findsOneWidget);
    // 停顿结束后才切到下一题。
    await tester.pump(_advanceDelay);
    await tester.pumpAndSettle();
    expect(find.text(_definitionOf(session, 1)), findsOneWidget);
    expect(find.text(firstDefinition), findsNothing);
    // 记了一条答对记录；答完一题只逐次记点击，结算草稿留到整局收尾再生成。
    expect(store.recordWrites, hasLength(2));
    expect(store.recordWrites.where((write) => write.isCorrect), hasLength(1));
    expect(store.finishes, isEmpty);

    // 卸载页面，让计时器全部清理，避免测试结束时挂起。
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('续玩：直接落在当前轮，历史题目不再堆在页面上', (WidgetTester tester) async {
    // 用户此前答完了前两轮，退出时停在第三轮。
    final words = _fiveWords();
    final session = _session(words, cursor: 2, elapsed: 5);
    final fixture = _progressFor(
      session,
      words: words,
      records: _completedRecords(session, 2),
    );
    await _pumpPage(tester, words: words, progress: fixture.progress);

    // 白卡只显示当前这一题，答过的两题不再堆在页面上。
    expect(find.text(_definitionOf(session, 0)), findsNothing);
    expect(find.text(_definitionOf(session, 1)), findsNothing);
    // 顶栏显示第 3 题。
    expect(find.text('3 / 5'), findsOneWidget);
    // 当前题只出现一次，且再等一会儿也不会冒出第二份。
    expect(find.text(_definitionOf(session, 2)), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text(_definitionOf(session, 2)), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('续玩：多匹配词轮只答对一个，重进后不误判完成并恢复已选词', (WidgetTester tester) async {
    // 「吃」同时匹配 eat 与 feed，用户只答对了 eat 就退出。
    final words = _eatWords();
    final session = _session(words, elapsed: 3);
    final definition = _definitionOf(session, 0);
    final fixture = _progressFor(
      session,
      words: words,
      records: <SessionRecord>[
        SessionRecord(
          id: 1,
          wordId: 1,
          meaningId: 201,
          input: 'eat',
          isCorrect: true,
          questionId: _questionIdOf(session, 0),
        ),
      ],
    );
    await _pumpPage(tester, words: words, progress: fixture.progress);

    // 仍在第 1 题「吃」——不能因为答对一个匹配词就把这道多匹配词轮判成已完成。
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.text(definition), findsOneWidget);
    // 已答对的 eat 恢复成填好的字母格（e-a-t），候选按钮恢复绿色禁用态。
    expect(_slotLetter(tester, wordId: 1, index: 0), 'e');
    expect(_slotLetter(tester, wordId: 1, index: 2), 't');
    // 还没答出的 feed 那组仍是空格子。
    expect(_slotLetter(tester, wordId: 2, index: 0), isNull);
    expect(
      _inkWellOf(tester, _candidateTexts(tester).indexOf('eat')).onTap,
      isNull,
    );
    // 这一轮还没答完，结算页不该出现。
    expect(
      find.byKey(const Key('settlement-meaningWordChoice')),
      findsNothing,
    );

    // 补答 feed：本轮两个匹配词都选出后，停顿结束才收尾。
    await _tapCandidate(tester, 'feed');
    expect(_slotLetter(tester, wordId: 2, index: 0), 'f');
    await tester.pump(_advanceDelay);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settlement-meaningWordChoice')),
      findsOneWidget,
    );
    // 本次只补答了 feed（eat 是上一局留下的记录），补完整局判定为已完成。
    expect(fixture.store.recordWrites, hasLength(1));
    expect(fixture.store.recordWrites.single.input, 'feed');
    expect(fixture.store.recordWrites.single.isCorrect, isTrue);
    expect(fixture.store.finishes.single.status, SessionStatus.completed);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('续玩：当前轮点错的候选恢复置灰，补答后正常推进', (WidgetTester tester) async {
    // 候选平时是按词库现算的，这里把这一轮的四个候选钉死，用例才能断言
    // 「点错的那一项在第几号位」：按字母升序排出来是
    // aardvark / eat / feed / zebra，点错的 zebra 落在第 3 号位。
    final words = _eatWords();
    final session = _session(
      words,
      elapsed: 2,
      pinnedDistractors: <String, List<String>>{
        '吃': <String>['aardvark', 'zebra'],
      },
    );
    final fixture = _progressFor(
      session,
      words: words,
      records: <SessionRecord>[
        SessionRecord(
          id: 1,
          // 点错的候选是现造的干扰词、没有自己的单词主键，记在这一轮的代表词上。
          wordId: 1,
          meaningId: 201,
          input: 'zebra',
          isCorrect: false,
          questionId: _questionIdOf(session, 0),
        ),
      ],
    );
    await _pumpPage(tester, words: words, progress: fixture.progress);

    // 当前轮仍是「吃」，点错过的 zebra 恢复置灰。
    expect(_candidateTexts(tester), <String>['aardvark', 'eat', 'feed', 'zebra']);
    expect(find.text('1 / 1'), findsOneWidget);
    expect(find.text(_definitionOf(session, 0)), findsOneWidget);
    expect(_inkWellOf(tester, 3).onTap, isNull);

    // 把 eat、feed 都补上，本轮完成、停顿结束后收尾。
    await _tapCandidate(tester, 'eat');
    await _tapCandidate(tester, 'feed');
    await tester.pump(_advanceDelay);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('settlement-meaningWordChoice')),
      findsOneWidget,
    );
    // 本次补答只新增了两条答对记录（eat、feed），没有新的点错写入；
    // 历史那次点错只影响现场恢复，不重复记账。
    expect(fixture.store.recordWrites, hasLength(2));
    expect(
      fixture.store.recordWrites.where((write) => write.isCorrect),
      hasLength(2),
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('全部答完进入结算页：三次一次选对、会话收尾为已完成', (WidgetTester tester) async {
    final words = _threeWords();
    final session = _session(words);
    final fixture = _progressFor(session, words: words);
    await _pumpPage(tester, words: words, progress: fixture.progress);

    // 按试卷顺序把三道题各一次选对。
    for (var index = 0; index < session.questions.length; index += 1) {
      await _tapCandidate(tester, _answersOf(session, index).single);
      await tester.pump(_advanceDelay);
      await tester.pumpAndSettle();
    }

    // 全部答完，进入共用结算页。
    expect(
      find.byKey(const Key('settlement-meaningWordChoice')),
      findsOneWidget,
    );
    expect(find.text('本轮复习结束'), findsOneWidget);
    expect(
      find.text('共 3 词 · 答对 3 · 答错 0', findRichText: true),
      findsOneWidget,
    );
    // 会话被判定为已完成。
    expect(fixture.store.finishes, hasLength(1));
    expect(fixture.store.finishes.single.status, SessionStatus.completed);

    await tester.pumpWidget(const SizedBox());
  });
}
