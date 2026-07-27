// material.dart 提供 MaterialApp 与 SizedBox。
import 'package:flutter/material.dart';
// flutter_test 提供页面交互和断言。
import 'package:flutter_test/flutter_test.dart';
// Tabler 图标用于核对完成状态图标规范。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入数据模型。
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';
// 引入默写页面与音频接口。
import 'package:my_english/pages/dictation/dictation_page.dart';
import 'package:my_english/services/word_audio.dart';
import 'package:my_english/store/settings.dart';

void main() {
  testWidgets('dictation handles wrong answers, stages and completion stats', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DictationPage(
          words: _words,
          audioPlayer: _ImmediateAudioPlayer(),
          accent: PronunciationAccent.american,
        ),
      ),
    );
    await tester.pump();

    // 首题先显示拼写选择阶段和完整四个选项。
    expect(find.text('听音，选出正确的单词'), findsOneWidget);
    expect(find.text('ability'), findsOneWidget);

    // 固定生成的交换字母干扰项应触发红色错误反馈且累计一次。
    await tester.tap(find.text('abliity'));
    await tester.pump();
    expect(find.text('不对，再试试'), findsOneWidget);
    // 新版原型只用红色文字反馈错误，不额外绘制错误图标。
    expect(find.byIcon(TablerIcons.x), findsNothing);

    // 正确拼写进入第一个词义的第一条释义。
    await tester.tap(find.text('ability'));
    await tester.pump();
    expect(find.text('n. · 选择释义 1/2'), findsOneWidget);
    await tester.tap(find.text('能力'));
    await tester.pump();
    expect(find.text('n. · 选择释义 2/2'), findsOneWidget);
    await tester.tap(find.text('才能'));
    await tester.pump();

    // 第二个单词没有释义，答对拼写后直接结束。
    expect(find.text('听音，选出正确的单词'), findsOneWidget);
    await tester.tap(find.text('abandon'));
    await tester.pump();
    expect(find.text('默写完成'), findsOneWidget);
    expect(find.text('共 2 个单词 · 答错 1 次'), findsOneWidget);
    expect(find.byIcon(TablerIcons.check), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dictation hint reveals leading letters progressively', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DictationPage(
          words: _words.take(1).toList(),
          audioPlayer: _ImmediateAudioPlayer(),
          accent: PronunciationAccent.american,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('_ _ _ _ _ _ _'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dictation-hint')));
    await tester.pump();
    expect(find.text('a _ _ _ _ _ _'), findsOneWidget);
    expect(find.text('已显示开头字母'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final _words = <Word>[
  const Word(
    id: 1,
    spelling: 'ability',
    meanings: <Meaning>[
      Meaning(index: 1, pos: 'n.', definitions: <String>['能力', '才能']),
    ],
  ),
  const Word(id: 2, spelling: 'abandon'),
];

class _ImmediateAudioPlayer implements WordAudioPlayer {
  @override
  Future<void> play(String spelling, PronunciationAccent accent) async {}

  @override
  Future<void> stop() async {}
}
