// flutter_test 提供 WidgetTester 与断言工具，用于驱动页面交互。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 被测页面与依赖模型。
import 'package:my_english/models/session.dart';
import 'package:my_english/models/session_record.dart';
import 'package:my_english/models/word.dart';
import 'package:my_english/models/meaning.dart';
import 'package:my_english/store/settings.dart';
import 'package:my_english/pages/meaning_match/meaning_match_page.dart';
import 'package:my_english/pages/review/services/session_progress.dart';

// 测试用内存 Store，避免触碰 MethodChannel。
import '../../support/memory_session_store.dart';

///
/// 构造一个仅含单条释义的单词，便于测试中确定“某单词对应哪条含义”。
///
/// [id] 单词主键；[meaningId] 该释义主键；[spelling] 英文；[definition] 唯一中文释义。
///
Word _word(int id, int meaningId, String spelling, String definition) => Word(
  id: id,
  spelling: spelling,
  meanings: [
    Meaning(id: meaningId, pos: 'n.', definition: definition),
  ],
);

///
/// 5 个单词，拼写与释义都互不相同，保证一组内左右一一对应且不会歧义。
///
List<Word> _fiveWords() => [
  _word(1, 101, 'apple', '苹果'),
  _word(2, 102, 'banana', '香蕉'),
  _word(3, 103, 'cat', '猫'),
  _word(4, 104, 'dog', '狗'),
  _word(5, 105, 'egg', '蛋'),
];

///
/// 按词表构造一局「进行中」的词义连连会话。
///
/// 数据列表元素是 [单词id, 含义id] 数对；词表只有一组（5 对）时就是单组棋盘。
///
Session _session(List<Word> words, {int cursor = 0, int elapsed = 0}) => Session(
  id: 1,
  module: ReviewModule.meaningMatch,
  kind: SessionKind.daily,
  status: SessionStatus.active,
  wordSetId: 1,
  items: <List<int>>[
    for (final word in words)
      <int>[word.id!, word.allMeanings.single.id!],
  ],
  cursor: cursor,
  elapsed: elapsed,
  date: '2026-08-29',
  createdAt: DateTime.now(),
);

///
/// 把页面装进 MaterialApp 并首次泵一帧。
///
/// [records] 传入历史点击记录用于续玩恢复；[elapsed] 是已用秒数。
///
Future<void> _pumpPage(
  WidgetTester tester, {
  required List<Word> words,
  List<SessionRecord> records = const <SessionRecord>[],
  int elapsed = 0,
  SettingsStore? settings,
}) async {
  final progress = SessionProgress(
    store: MemorySessionStore(),
    session: _session(words, elapsed: elapsed),
    records: records,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: MeaningMatchPage(
        words: words,
        title: '词义连连',
        progress: progress,
        settings: settings,
      ),
    ),
  );
  // 跑一帧让 initState 完成、倒计时与棋盘建好。
  await tester.pump();
}

///
/// 取出某张候选卡「卡片本体」的装饰（底色 + 描边）。
///
/// 一张卡里有两个 AnimatedContainer：方形的卡片本体，和内侧那颗正圆锚点。
/// 这里只挑方形的那个，避免误把锚点的装饰当成卡片本体。
BoxDecoration _cardDecoration(WidgetTester tester, Key cardKey) {
  final containers = tester.widgetList<AnimatedContainer>(
    find.descendant(
      of: find.byKey(cardKey),
      matching: find.byType(AnimatedContainer),
    ),
  );
  for (final container in containers) {
    final decoration = container.decoration;
    if (decoration is BoxDecoration && decoration.shape == BoxShape.rectangle) {
      return decoration;
    }
  }
  throw StateError('未找到候选卡本体的装饰');
}

///
/// 取出某张候选卡当前的描边颜色。
Color _cardBorderColor(WidgetTester tester, Key cardKey) =>
    (_cardDecoration(tester, cardKey).border! as Border).top.color;

void main() {
  testWidgets('页面能正常构建并显示 150 秒倒计时与 0/5 计数', (WidgetTester tester) async {
    await _pumpPage(tester, words: _fiveWords());
    // 顶栏计数初始为 0 / 5（5 个单词 = 5 对）。
    expect(find.text('0 / 5'), findsOneWidget);
    // 倒计时取自全局默认 150 秒 -> 02:30。
    expect(find.text('02:30'), findsOneWidget);
  });

  testWidgets('点击倒计时 +30 秒：显示变 03:00 且写入全局设置', (WidgetTester tester) async {
    final settings = SettingsStore.inMemory();
    await _pumpPage(tester, words: _fiveWords(), settings: settings);
    // 点击右上角倒计时。
    await tester.tap(find.byKey(const Key('meaning-match-countdown')));
    await tester.pump();
    // 当前剩余 180 秒 -> 03:00。
    expect(find.text('03:00'), findsOneWidget);
    // 同时全局设置也 +30（150 -> 180）。
    expect(settings.meaningMatchDuration, 180);
  });

  testWidgets('正确配对：左卡点 apple 再点其释义苹果，计数变为 1/5', (WidgetTester tester) async {
    await _pumpPage(tester, words: _fiveWords());
    // 先点左列 apple。
    await tester.tap(find.byKey(const Key('mm-left-0')));
    await tester.pump();
    // 再点右列显示“苹果”的卡片（apple 的唯一释义）。
    await tester.tap(find.text('苹果'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // 一对连成，计数 0/5 -> 1/5。
    expect(find.text('1 / 5'), findsOneWidget);
  });

  testWidgets('错误配对：左卡点 apple 再点错误释义，计数仍为 0/5', (WidgetTester tester) async {
    await _pumpPage(tester, words: _fiveWords());
    await tester.tap(find.byKey(const Key('mm-left-0')));
    await tester.pump();
    // 点右列“香蕉”（apple 的错误释义）应判错，不改变计数。
    await tester.tap(find.text('香蕉'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('0 / 5'), findsOneWidget);
  });

  testWidgets('选中态：点中的左卡描边转为蓝色主色', (WidgetTester tester) async {
    await _pumpPage(tester, words: _fiveWords());
    // 未点选时是中性灰描边：三个颜色通道彼此接近。
    final idle = _cardBorderColor(tester, const Key('mm-left-0'));
    expect((idle.r - idle.b).abs(), lessThan(0.08));

    await tester.tap(find.byKey(const Key('mm-left-0')));
    await tester.pump();

    // 选中后换成品牌蓝：蓝色通道明显高于红色通道。
    final selected = _cardBorderColor(tester, const Key('mm-left-0'));
    expect(selected.b, greaterThan(selected.r));
  });

  testWidgets('连对态：两张卡变绿并淡出到 45%', (WidgetTester tester) async {
    await _pumpPage(tester, words: _fiveWords());
    await tester.tap(find.byKey(const Key('mm-left-0')));
    await tester.pump();
    await tester.tap(find.text('苹果'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 描边转绿：绿色通道同时高于红蓝两个通道。
    final matched = _cardBorderColor(tester, const Key('mm-left-0'));
    expect(matched.g, greaterThan(matched.r));
    expect(matched.g, greaterThan(matched.b));

    // 整卡淡到补充稿规定的 45%。
    final opacity = tester.widget<AnimatedOpacity>(
      find
          .descendant(
            of: find.byKey(const Key('mm-left-0')),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
    expect(opacity.opacity, closeTo(0.45, 0.001));
  });

  testWidgets('连错态：两张卡转红并抖动，抖完自动恢复', (WidgetTester tester) async {
    await _pumpPage(tester, words: _fiveWords());
    await tester.tap(find.byKey(const Key('mm-left-0')));
    await tester.pump();
    // 点右列“香蕉”（apple 的错误释义）触发连错反馈。
    await tester.tap(find.text('香蕉'));
    await tester.pump();

    // 描边转红：红色通道同时高于绿蓝两个通道。
    final wrong = _cardBorderColor(tester, const Key('mm-left-0'));
    expect(wrong.r, greaterThan(wrong.g));
    expect(wrong.r, greaterThan(wrong.b));

    // 抖动中卡片确实被水平甩开了（补充稿 errorJolt 的第一段是往左 6 像素）。
    await tester.pump(const Duration(milliseconds: 80));
    final shifted = tester.widget<Transform>(
      find
          .descendant(
            of: find.byKey(const Key('mm-left-0')),
            matching: find.byType(Transform),
          )
          .at(1),
    );
    expect(shifted.transform.getTranslation().x.abs(), greaterThan(0));

    // 0.4 秒后红色自动收掉，卡片回到中性描边等待重新点选。
    await tester.pump(const Duration(milliseconds: 400));
    final restored = _cardBorderColor(tester, const Key('mm-left-0'));
    expect((restored.r - restored.b).abs(), lessThan(0.08));
  });

  testWidgets('连错反馈期间忽略点击，抖完才能继续连', (WidgetTester tester) async {
    await _pumpPage(tester, words: _fiveWords());
    await tester.tap(find.byKey(const Key('mm-left-0')));
    await tester.pump();
    await tester.tap(find.text('香蕉'));
    await tester.pump();

    // 红色还没播完就抢着连下一对，本次点击应被整段忽略。
    await tester.tap(find.byKey(const Key('mm-left-1')));
    await tester.pump();
    await tester.tap(find.text('香蕉'));
    await tester.pump();
    expect(find.text('0 / 5'), findsOneWidget);

    // 等抖动播完解锁后，同样的两下就能正常连成一对。
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('mm-left-1')));
    await tester.pump();
    await tester.tap(find.text('香蕉'));
    await tester.pump();
    expect(find.text('1 / 5'), findsOneWidget);
  });

  testWidgets('会话续玩：回放记录恢复已匹配 1 对与剩余 90 秒', (WidgetTester tester) async {
    // 用户此前连对了 apple ↔ 苹果，用时 60 秒后退出。
    await _pumpPage(
      tester,
      words: _fiveWords(),
      elapsed: 60,
      records: const <SessionRecord>[
        SessionRecord(id: 1, wordId: 1, meaningId: 101, input: '苹果', isCorrect: true),
      ],
    );
    // 续玩恢复计数 1/5。
    expect(find.text('1 / 5'), findsOneWidget);
    // 续玩恢复剩余 90 秒（150 − 60）-> 01:30。
    expect(find.text('01:30'), findsOneWidget);
  });
}
