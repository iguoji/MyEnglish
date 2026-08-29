// flutter_test 提供页面交互与断言。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 引入数据模型。
import 'package:my_english/models/session.dart';
import 'package:my_english/models/session_record.dart';
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';
// 被测页面与其布局尺寸表。
import 'package:my_english/pages/spelling_reinforcement/spelling_reinforcement_page.dart';
import 'package:my_english/pages/spelling_reinforcement/widgets/spelling_layout.dart';
import 'package:my_english/pages/review/services/session_progress.dart';
import 'package:my_english/services/word_audio.dart';
import 'package:my_english/store/settings.dart';

// 测试用内存会话 Store，避免触碰 MethodChannel。
import '../../support/memory_session_store.dart';

///
/// 造一个带单条中文释义的单词；[syllables] 直接给出切分方案，测试完全可控。
///
Word _word(int id, String spelling, String definition, {List<String> syllables = const <String>[]}) =>
    Word(
      id: id,
      spelling: spelling,
      meanings: <Meaning>[
        Meaning(id: id * 100, pos: 'n.', definition: definition),
      ],
      syllables: syllables,
    );

///
/// 把页面装进 MaterialApp 并完成准备阶段。
///
/// [records] 传入历史点击记录用于续玩恢复；[cursor] 是上次保存的单词下标。
///
Future<MemorySessionStore> _pumpPage(
  WidgetTester tester, {
  List<Word>? words,
  int cursor = 0,
  List<SessionRecord> records = const <SessionRecord>[],
}) async {
  final wordList =
      words ??
      <Word>[
        _word(1, 'tradition', '传统', syllables: <String>['tra', 'di', 'tion']),
      ];
  final store = MemorySessionStore();
  final session = Session(
    id: 1,
    module: ReviewModule.spellingReinforcement,
    kind: SessionKind.daily,
    status: SessionStatus.active,
    wordSetId: 1,
    items: <int>[for (final word in wordList) word.id!],
    cursor: cursor,
    elapsed: 0,
    date: '2026-08-25',
    createdAt: DateTime.now(),
  );
  final progress = SessionProgress(store: store, session: session, records: records);
  await tester.pumpWidget(
    MaterialApp(
      home: SpellingReinforcementPage(
        words: wordList,
        title: '拼写巩固',
        progress: progress,
        audioPlayer: _SilentAudioPlayer(),
        accent: PronunciationAccent.american,
      ),
    ),
  );
  // 准备当前词是异步的，多泵几帧让切分方案与候选池就绪。
  await tester.pump();
  await tester.pump();
  return store;
}

void main() {
  testWidgets('候选片段与占位格按内容定宽，同一行能并排放下', (tester) async {
    await _pumpPage(tester);

    final screenWidth = tester.getSize(find.byType(MaterialApp)).width;

    // 占位格：3 格，每格宽度不该接近整行宽（曾因内部用撑满的居中导致一格一行）。
    final slotRects = <Rect>[
      for (var i = 0; i < 3; i += 1)
        tester.getRect(find.byKey(Key('spelling-slot-$i'))),
    ];
    for (final rect in slotRects) {
      expect(
        rect.width,
        lessThan(screenWidth / 2),
        reason: '占位格被撑满会导致每格独占一行',
      );
      expect(rect.width, greaterThanOrEqualTo(SpellingLayout.slotMinWidth));
    }
    // 三个占位格必须在同一行。
    expect(slotRects[1].top, slotRects[0].top);
    expect(slotRects[2].top, slotRects[0].top);

    // 候选片段同理：至少前两个在同一行且各自远窄于整行。
    final chunk0 = tester.getRect(find.byKey(const Key('spelling-chunk-0')));
    final chunk1 = tester.getRect(find.byKey(const Key('spelling-chunk-1')));
    expect(chunk0.width, lessThan(screenWidth / 2));
    expect(chunk0.width, greaterThanOrEqualTo(SpellingLayout.chunkMinWidth));
    expect(chunk1.top, chunk0.top, reason: '候选片段被撑满会导致每个独占一行');
  });

  testWidgets('逐字母模式的字母格保持 40×40 并排列在同一行', (tester) async {
    await _pumpPage(
      tester,
      words: <Word>[
        _word(2, 'bowl', '碗', syllables: <String>['bowl']),
      ],
    );

    final rects = <Rect>[
      for (var i = 0; i < 4; i += 1)
        tester.getRect(find.byKey(Key('spelling-slot-$i'))),
    ];
    for (final rect in rects) {
      expect(rect.width, SpellingLayout.letterSlotSize);
      expect(rect.top, rects[0].top);
    }
    // 逐字母模式才有键盘。
    expect(find.byKey(const Key('spelling-key-a')), findsOneWidget);

    // 键盘每一行都要真正居中：行尾多挂一个间隔会让整行左偏。
    final screenWidth = tester.getSize(find.byType(MaterialApp)).width;
    for (final row in const <List<String>>[
      <String>['q', 'p'],
      <String>['a', 'l'],
    ]) {
      final left = tester.getRect(find.byKey(Key('spelling-key-${row[0]}')));
      final right = tester.getRect(find.byKey(Key('spelling-key-${row[1]}')));
      expect(
        (left.left + right.right) / 2,
        moreOrLessEquals(screenWidth / 2, epsilon: 0.5),
        reason: '${row[0]}–${row[1]} 这一行没有居中',
      );
    }
  });

  testWidgets('续玩：已答对的词直接跳过，当前词从开头重新开始', (tester) async {
    // 用户此前拼完了 tradition，退出时停在第二个词 bowl。
    final store = await _pumpPage(
      tester,
      words: <Word>[
        _word(1, 'tradition', '传统', syllables: <String>['tra', 'di', 'tion']),
        _word(2, 'bowl', '碗', syllables: <String>['bowl']),
      ],
      cursor: 1,
      records: const <SessionRecord>[
        SessionRecord(id: 1, wordId: 1, meaningId: null, input: 'tradition', isCorrect: true),
      ],
    );

    // 当前词是 bowl：4 个逐字母占位格。
    expect(find.byKey(const Key('spelling-slot-3')), findsOneWidget);
    // 已答对的 tradition 不会重复出题（tra 片段不在候选池里）。
    expect(find.text('tra'), findsNothing);
    // 页面没有异常。
    expect(tester.takeException(), isNull);
    // tradition 已写入结算（答对记录），bowl 尚未结算。
    expect(store.settles.map((settle) => settle.wordId), isNot(contains(1)));
  });

  testWidgets('续玩：当前词拼了一半不恢复，错误次数继续累计', (tester) async {
    // 用户上一局在 tradition 上点错过一块（input 记的是那块的文本）。
    await _pumpPage(
      tester,
      cursor: 0,
      records: const <SessionRecord>[
        SessionRecord(id: 1, wordId: 1, meaningId: null, input: 'tra', isCorrect: false),
      ],
    );

    // 占位格从空白重新开始（v2.0 不恢复「拼了一半」的现场）。
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('spelling-slot-0')),
              matching: find.byType(Text),
            ),
          )
          .data,
      '',
      reason: '续玩应从当前词的开头重新拼',
    );
    // 页面仍可正常作答，不抛异常。
    expect(tester.takeException(), isNull);
  });
}

///
/// 不发声的音频实现：Widget 测试不触碰原生通道。
class _SilentAudioPlayer extends WordAudioPlayer {
  @override
  Future<void> play(String spelling, PronunciationAccent accent) async {}

  @override
  Future<void> stop() async {}
}
