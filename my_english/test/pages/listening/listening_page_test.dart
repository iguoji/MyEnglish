// material.dart 提供测试外层 MaterialApp。
import 'package:flutter/material.dart';
// flutter_test 提供 Widget 测试驱动与断言。
import 'package:flutter_test/flutter_test.dart';
// Tabler 图标用于确认播放状态没有回退成文字符号。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入单词与释义模型。
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';
// 引入随身听页面。
import 'package:my_english/pages/listening/listening_page.dart';
// 引入音频接口与口音枚举。
import 'package:my_english/services/word_audio.dart';
import 'package:my_english/store/settings.dart';

void main() {
  testWidgets('listening page mirrors player layout and reveal interaction', (
    tester,
  ) async {
    final audio = _ImmediateAudioPlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: ListeningPage(
          words: _words,
          audioPlayer: audio,
          accent: PronunciationAccent.american,
          definitionSeparator: '，',
        ),
      ),
    );
    await tester.pump();

    // 顶部进度、搜索框和隐藏答案提示全部存在。
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byKey(const Key('listening-search')), findsOneWidget);
    expect(find.text('按住卡片临时查看，点右上角眼睛常显'), findsOneWidget);
    expect(find.text('ability'), findsNothing);

    // 眼睛按钮常显答案，使用的是 Tabler eye 图标而非文字图标。
    await tester.tap(find.byKey(const Key('toggle-listening-answer')));
    await tester.pump();
    expect(find.text('ability'), findsWidgets);
    // 同一词性的中文定义使用设置符号连接在一个 Text 中。
    expect(find.text('能力，才能'), findsOneWidget);
    expect(find.text('能力'), findsNothing);
    expect(find.text('才能'), findsNothing);
    expect(find.byIcon(TablerIcons.eye), findsOneWidget);

    // 顶栏图标的可见画布分别贴齐左右 20 像素边距。
    expect(
      // getTopLeft 相当于读取小程序节点的 boundingClientRect().left。
      tester.getTopLeft(find.byIcon(TablerIcons.chevronLeft)).dx,
      closeTo(20, 0.01),
    );
    expect(
      // getBottomRight(...).dx 就是可见设置图标最右侧的横坐标。
      tester.getBottomRight(find.byIcon(TablerIcons.settings)).dx,
      closeTo(780, 0.01),
    );

    // 上一个图标在文字左侧，下一个图标在文字右侧。
    expect(
      tester.getCenter(find.byIcon(TablerIcons.playerTrackPrev)).dx,
      lessThan(tester.getCenter(find.text('上一个')).dx),
    );
    expect(
      tester.getCenter(find.byIcon(TablerIcons.playerTrackNext)).dx,
      greaterThan(tester.getCenter(find.text('下一个')).dx),
    );

    // 暂停后主按钮切换成 Tabler 播放图标。
    await tester.tap(find.byKey(const Key('toggle-listening-playback')));
    await tester.pump();
    expect(find.byIcon(TablerIcons.playerPlay), findsOneWidget);

    // 设置面板完整包含三项原型设置。
    await tester.tap(find.byKey(const Key('open-listening-settings')));
    await tester.pumpAndSettle();
    expect(find.text('播放次数'), findsOneWidget);
    expect(find.text('播放间隔(秒)'), findsOneWidget);
    expect(find.text('列表循环'), findsOneWidget);
    expect(find.byKey(const Key('listening-loop-switch')), findsOneWidget);

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

/// 立即完成的播放器让测试无需网络和原生 MediaPlayer。
class _ImmediateAudioPlayer implements WordAudioPlayer {
  @override
  Future<void> play(String spelling, PronunciationAccent accent) async {}

  @override
  Future<void> stop() async {}
}
