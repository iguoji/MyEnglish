// flutter_test 提供页面交互与断言。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 引入数据模型。
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/review_session.dart';
import 'package:my_english/models/word.dart';
// 被测页面与其布局尺寸表。
import 'package:my_english/pages/spelling_reinforcement/spelling_reinforcement_page.dart';
import 'package:my_english/pages/spelling_reinforcement/widgets/spelling_layout.dart';
// 音节服务：测试注入内存 Store，切法完全可控。
import 'package:my_english/services/syllable_service.dart';
import 'package:my_english/services/word_audio.dart';
import 'package:my_english/store/settings.dart';

import '../../support/memory_review_stores.dart';
import '../../support/memory_syllable_store.dart';
import '../../support/recording_review_record_store.dart';

///
/// 造一个带单条中文释义的单词。
Word _word(int id, String spelling, String definition) => Word(
  id: id,
  spelling: spelling,
  meanings: [
    Meaning(index: 0, pos: 'n.', definitions: [definition]),
  ],
);

///
/// 一局只含 tradition 的会话，切法固定为 tra / di / tion。
///
/// [state] 用于伪造「中途退出后的快照」，验证续玩分支。
Future<RecordingReviewRecordStore> _pumpPage(
  WidgetTester tester, {
  Map<String, Object?> state = const <String, Object?>{},
  List<Word>? words,
  Map<String, List<String>> divisions = const <String, List<String>>{
    'tradition': <String>['tra', 'di', 'tion'],
  },
}) async {
  final store = InMemorySyllableStore();
  for (final entry in divisions.entries) {
    await store.saveDivision(entry.key, entry.value, 'algo');
  }
  final wordList = words ?? <Word>[_word(1, 'tradition', '传统')];
  final session = ReviewSession(
    id: 1,
    module: ReviewModule.spellingReinforcement,
    kind: ReviewSessionKind.daily,
    status: ReviewSessionStatus.active,
    wordSetId: 1,
    wordIds: wordList.map((word) => word.id!).toList(),
    state: state,
    wrongTotal: 0,
    sessionDate: '2026-08-25',
    createdAt: DateTime.now(),
  );
  final records = RecordingReviewRecordStore();
  await tester.pumpWidget(
    MaterialApp(
      home: SpellingReinforcementPage(
        words: wordList,
        title: '拼写巩固',
        reviewSession: session,
        audioPlayer: _SilentAudioPlayer(),
        accent: PronunciationAccent.american,
        reviewSessionStore: MemoryReviewSessionStore(
          // 把这一局塞进内存 Store，页面保存进度时才找得到它。
          initial: <ReviewSession>[session],
        ),
        recordStore: records,
        syllableService: SyllableService(store),
      ),
    ),
  );
  // 切分方案是异步取的，多泵几帧让准备阶段结束。
  await tester.pump();
  await tester.pump();
  return records;
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
      words: <Word>[_word(2, 'bowl', '碗')],
      divisions: const <String, List<String>>{
        // 拆不开的词：整词一块，页面应落到逐字母模式。
        'bowl': <String>['bowl'],
      },
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

  testWidgets('续玩时恢复当前词已填的格子', (tester) async {
    await _pumpPage(
      tester,
      state: <String, Object?>{
        'wordIndex': 0,
        // 上次退出前已经填对了 tra、di 两格。
        'filledChunks': 2,
        'typedLetters': '',
        'currentWrong': 0,
        'currentRevealed': false,
        'outcomes': <Object?>[],
        'recordedIndexes': <Object?>[],
        'elapsedMs': 0,
        'errors': 0,
        'completed': false,
      },
    );

    expect(find.text('tra'), findsWidgets, reason: '第一格应恢复成 tra');
    expect(
      tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('spelling-slot-0')),
          matching: find.byType(Text),
        ),
      ).data,
      'tra',
    );
    expect(
      tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('spelling-slot-1')),
          matching: find.byType(Text),
        ),
      ).data,
      'di',
    );
    // 第三格还没填，保持空白。
    expect(
      tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('spelling-slot-2')),
          matching: find.byType(Text),
        ),
      ).data,
      '',
    );
  });

  testWidgets('续玩到「格子已填满但还没翻页」的快照时不崩溃且能继续', (tester) async {
    // 用户在最后一格填完、翻页停顿的 0.5 秒内退出，快照里 filledChunks 已等于片段数。
    final records = await _pumpPage(
      tester,
      state: <String, Object?>{
        'wordIndex': 0,
        'filledChunks': 3,
        'typedLetters': '',
        'currentWrong': 0,
        'currentRevealed': false,
        'outcomes': <Object?>[],
        'recordedIndexes': <Object?>[],
        'elapsedMs': 0,
        'errors': 0,
        'completed': false,
      },
    );

    // 此时点任意一个候选片段都不该抛异常（干扰项还是可点的）。
    for (var i = 0; i < 9; i += 1) {
      final chunk = find.byKey(Key('spelling-chunk-$i'));
      if (chunk.evaluate().isEmpty) continue;
      await tester.tap(chunk, warnIfMissed: false);
      // 判错会锁输入 350 毫秒，泵够时间再点下一个，否则后面的点击会被忽略。
      await tester.pump(
        const Duration(milliseconds: SpellingLayout.shakeDurationMs + 50),
      );
      expect(tester.takeException(), isNull, reason: '第 $i 个候选片段点击后抛异常');
    }

    // 而且这一局要能自己走完，不能卡在填满的状态里。
    await tester.pump(
      const Duration(milliseconds: SpellingLayout.wordAdvanceDelayMs + 200),
    );
    expect(records.writes, isNotEmpty, reason: '填满的词应当被判定完成并写记录');
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
