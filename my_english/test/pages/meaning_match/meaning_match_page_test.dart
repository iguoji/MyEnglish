// flutter_test 提供 WidgetTester 与断言工具，用于驱动页面交互。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 被测页面与依赖模型。
import 'package:my_english/models/word.dart';
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/review_session.dart';
import 'package:my_english/store/settings.dart';
import 'package:my_english/pages/meaning_match/meaning_match_page.dart';

// 测试用内存 Store，避免触碰 MethodChannel。
import '../../support/memory_review_stores.dart';
import '../../support/recording_review_record_store.dart';

///
/// 构造一个仅含单条释义的单词，便于测试中确定“某单词对应哪条含义”。
///
/// [id] 单词主键；[spelling] 英文；[definition] 唯一中文释义。
///
Word _word(int id, String spelling, String definition) => Word(
  id: id,
  spelling: spelling,
  meanings: [
    Meaning(index: 0, pos: 'n.', definitions: [definition]),
  ],
);

///
/// 5 个单词，拼写与释义都互不相同，保证一组内左右一一对应且不会歧义。
///
List<Word> _fiveWords() => [
  _word(1, 'apple', '苹果'),
  _word(2, 'banana', '香蕉'),
  _word(3, 'cat', '猫'),
  _word(4, 'dog', '狗'),
  _word(5, 'egg', '蛋'),
];

///
/// 把页面装进 MaterialApp 并首次泵一帧。
///
Future<void> _pumpPage(
  WidgetTester tester, {
  required List<Word> words,
  Map<String, Object?> state = const <String, Object?>{},
  int wrongTotal = 0,
  ReviewSessionKind kind = ReviewSessionKind.daily,
  SettingsStore? settings,
  MemoryReviewSessionStore? sessionStore,
}) async {
  // 页面必须拿到一局会话才能开工；这里现造一局「进行中」的主线。
  final session = ReviewSession(
    id: 1,
    module: ReviewModule.meaningMatch,
    kind: kind,
    status: ReviewSessionStatus.active,
    wordSetId: 1,
    wordIds: words.map((word) => word.id!).toList(),
    state: state,
    wrongTotal: wrongTotal,
    sessionDate: '2026-08-23',
    createdAt: DateTime.now(),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: MeaningMatchPage(
        words: words,
        title: '词义连连',
        reviewSession: session,
        reviewSessionStore: sessionStore ?? MemoryReviewSessionStore(),
        // 记录写入走内存实现，测试完全不触碰 MethodChannel。
        recordStore: RecordingReviewRecordStore(),
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
///
/// @param  WidgetTester  tester 当前测试驱动器。
/// @param  Key  cardKey 候选卡的外层 Key，如 `mm-left-0`。
/// @return BoxDecoration 卡片本体当前的目标装饰。
///
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
///
/// @param  WidgetTester  tester 当前测试驱动器。
/// @param  Key  cardKey 候选卡的外层 Key。
/// @return Color 描边颜色。
///
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

  testWidgets('会话续玩：恢复已匹配 1 对与剩余 90 秒', (WidgetTester tester) async {
    await _pumpPage(
      tester,
      words: _fiveWords(),
      state: <String, Object?>{
        'groupIndex': 0,
        'matchedLeft': [0],
        'matchedRight': [1],
        'remainingMs': 90000,
        'matchedPairs': 1,
        'totalPairs': 5,
        'completed': false,
        'timedOut': false,
        'bestStreak': 1,
        'errors': 0,
      },
    );
    // 续玩恢复计数 1/5。
    expect(find.text('1 / 5'), findsOneWidget);
    // 续玩恢复剩余 90 秒 -> 01:30。
    expect(find.text('01:30'), findsOneWidget);
  });
}
