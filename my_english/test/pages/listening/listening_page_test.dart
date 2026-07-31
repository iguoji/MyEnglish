// dart:io 读取页面源码，用回归测试禁止重新加入负数视觉定位。
import 'dart:io';

// material.dart 提供测试外层 MaterialApp。
import 'package:flutter/material.dart';
// flutter_test 提供 Widget 测试驱动与断言。
import 'package:flutter_test/flutter_test.dart';
// Tabler 图标用于确认播放状态没有回退成文字符号。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入单词与释义模型。
import 'package:my_english/models/learning_session.dart';
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';
// 引入随身听页面。
import 'package:my_english/pages/listening/listening_page.dart';
// 引入随身听布局尺寸，用与生产代码相同的标准核对圆角。
import 'package:my_english/pages/listening/widgets/listening_layout.dart';
// 引入音频接口与口音枚举。
import 'package:my_english/services/word_audio.dart';
import 'package:my_english/store/settings.dart';

import '../../support/memory_learning_session_store.dart';

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

    // 搜索框和两个跳转按钮必须共享同一个 32 像素工具栏高度。
    final searchRect = tester.getRect(
      find.byKey(const Key('listening-search')),
    );
    final scrollTopRect = tester.getRect(
      find.byKey(const Key('listening-scroll-top')),
    );
    final scrollBottomRect = tester.getRect(
      find.byKey(const Key('listening-scroll-bottom')),
    );
    expect(searchRect.height, closeTo(32, 0.01));
    expect(scrollTopRect.height, closeTo(searchRect.height, 0.01));
    expect(scrollBottomRect.height, closeTo(searchRect.height, 0.01));
    expect(scrollTopRect.top, closeTo(searchRect.top, 0.01));
    expect(scrollBottomRect.top, closeTo(searchRect.top, 0.01));

    // 答案卡必须由同一个 Material 负责圆角、边框和裁剪，防止圆角边框被外层裁掉。
    final answerSurface = tester.widget<Material>(
      find.byKey(const Key('listening-answer-surface')),
    );
    // shape 在运行时应当是可以同时描边的圆角矩形。
    expect(answerSurface.shape, isA<RoundedRectangleBorder>());
    // 读出具体形状，便于继续核对圆角和边框宽度。
    final answerShape = answerSurface.shape! as RoundedRectangleBorder;
    // 圆角必须与集中尺寸表保持一致。
    expect(
      answerShape.borderRadius,
      BorderRadius.circular(ListeningLayout.cardRadius),
    );
    // 1 像素边框可以保持卡片边界清晰，又不会修改内部布局尺寸。
    expect(answerShape.side.width, 1);
    // 抗锯齿裁剪应与 Material 的圆角轮廓一起工作。
    expect(answerSurface.clipBehavior, Clip.antiAlias);

    // 眼睛按钮相对答案卡右上角使用 8 像素正数边距。
    final answerCardRect = tester.getRect(
      find.byKey(const Key('listening-answer-card')),
    );
    final eyeButtonRect = tester.getRect(
      find.byKey(const Key('toggle-listening-answer')),
    );
    final hiddenEyeCanvasRect = tester.getRect(find.byIcon(TablerIcons.eyeOff));
    expect(eyeButtonRect.top, closeTo(answerCardRect.top + 8, 0.01));
    expect(eyeButtonRect.right, closeTo(answerCardRect.right - 8, 0.01));
    // 图标画布在按钮内部直接贴右上角，不再依赖负数补偿。
    expect(hiddenEyeCanvasRect.top, closeTo(eyeButtonRect.top, 0.01));
    expect(hiddenEyeCanvasRect.right, closeTo(eyeButtonRect.right, 0.01));

    // 先记录骨架态三个布局槽位的位置，用来模拟用户按住卡片前的坐标。
    final hiddenSpellingRect = tester.getRect(
      find.byKey(const Key('listening-spelling-slot')),
    );
    final hiddenPosRect = tester.getRect(
      find.byKey(const Key('listening-pos-1')),
    );
    final hiddenDefinitionRect = tester.getRect(
      find.byKey(const Key('listening-definition-1')),
    );
    // startGesture 只触发按下而不立即抬起，对应真机手指持续按住答案卡。
    final peekGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('listening-answer-card'))),
    );
    await tester.pump();
    // 按住后真实单词出现，但单词、词性和释义槽位都不能移动或变高。
    expect(find.text('ability'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('listening-spelling-slot'))),
      hiddenSpellingRect,
    );
    expect(
      tester.getRect(find.byKey(const Key('listening-pos-1'))),
      hiddenPosRect,
    );
    expect(
      tester.getRect(find.byKey(const Key('listening-definition-1'))),
      hiddenDefinitionRect,
    );
    // 抬起手指恢复骨架态，供后面的常显按钮继续验证。
    await peekGesture.up();
    await tester.pump();
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

    // 返回按钮的 34 像素点击区域仍从页面 20 像素边距开始。
    expect(
      tester.getTopLeft(find.byKey(const Key('close-listening'))).dx,
      closeTo(20, 0.01),
    );
    // 箭头画布通过 Align 直接对齐按钮左边，不再使用 Transform 或负数偏移。
    expect(
      tester.getTopLeft(find.byIcon(TablerIcons.chevronLeft)).dx,
      closeTo(20, 0.01),
    );
    // 设置图标的可见画布保持贴齐右侧 20 像素边距。
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
    // “完成”的可见文字应贴齐面板 20 像素右边距，不能被按钮默认内边距向左推。
    // 桌面测试会限制底部面板宽度，因此先读取面板自身的最右侧坐标。
    final settingsSheetRight = tester
        .getBottomRight(find.byKey(const Key('listening-settings-sheet')))
        .dx;
    expect(
      // 从面板右边缘减去设计约定的 20 像素，就是“完成”文字的目标右边缘。
      tester
          .getBottomRight(find.byKey(const Key('listening-settings-done')))
          .dx,
      closeTo(settingsSheetRight - 20, 0.01),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('multiline definitions keep later meanings fixed while peeking', (
    tester,
  ) async {
    // 使用接近手机的窄画布，确保第一条长释义真实发生换行。
    await tester.binding.setSurfaceSize(const Size(390, 844));
    // 测试结束后恢复默认画布，避免影响同文件后续用例。
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // 两条词性让测试可以观察第一条多行释义是否把第二条词性向下挤。
    const words = <Word>[
      Word(
        spelling: 'layout',
        meanings: <Meaning>[
          Meaning(
            index: 2,
            pos: 'n.',
            definitions: <String>['布局以及一段足够长的中文释义，用来确认窄屏幕中换行后的真实高度也会在骨架状态提前保留'],
          ),
          Meaning(index: 1, pos: 'v.', definitions: <String>['安排']),
        ],
      ),
    ];
    // 注入立即完成的播放器，测试只关注答案卡布局。
    await tester.pumpWidget(
      MaterialApp(
        home: ListeningPage(
          words: words,
          audioPlayer: _ImmediateAudioPlayer(),
          accent: PronunciationAccent.american,
        ),
      ),
    );
    await tester.pump();

    // 保存骨架态第一条释义槽位和第二条词性的坐标。
    final hiddenDefinitionRect = tester.getRect(
      find.byKey(const Key('listening-definition-2')),
    );
    final hiddenSecondPosRect = tester.getRect(
      find.byKey(const Key('listening-pos-1')),
    );
    // 按住答案卡切换成真实的多行释义。
    final peekGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('listening-answer-card'))),
    );
    await tester.pump();

    // 第一条释义槽位高度和第二条词性位置必须逐像素保持不变。
    expect(
      tester.getRect(find.byKey(const Key('listening-definition-2'))),
      hiddenDefinitionRect,
    );
    expect(
      tester.getRect(find.byKey(const Key('listening-pos-1'))),
      hiddenSecondPosRect,
    );

    // 主动抬起手指并销毁页面，确保播放计时器一并清理。
    await peekGesture.up();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'listening restores and updates the persisted playback position',
    (tester) async {
      // 历史会话停在第二个词，并且离开前处于暂停状态。
      const session = LearningSession(
        type: LearningSessionType.listening,
        wordIds: <int>[1, 2],
        state: <String, Object?>{
          'index': 1,
          'completedRepeats': 1,
          'isPlaying': false,
          'revealAll': true,
          'repeat': 3,
          'interval': 4,
          'loop': false,
        },
      );
      // 内存 Store 用于观察页面进入和跳词后写出的最新快照。
      final sessionStore = MemoryLearningSessionStore(<LearningSession>[
        session,
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: ListeningPage(
            words: _words,
            audioPlayer: _ImmediateAudioPlayer(),
            accent: PronunciationAccent.american,
            initialSession: session,
            sessionStore: sessionStore,
          ),
        ),
      );
      await tester.pump();

      // 首帧直接停在第二个词；暂停状态和显示答案偏好也完整恢复。
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.byIcon(TablerIcons.playerPlay), findsOneWidget);
      expect(find.byIcon(TablerIcons.eye), findsOneWidget);
      expect(sessionStore.sessions.single.state['index'], 1);

      // 主动回到上一个词后，页面立即把新下标覆盖进同一条会话。
      await tester.tap(find.text('上一个'));
      await tester.pump();
      expect(find.text('1 / 2'), findsOneWidget);
      expect(sessionStore.sessions.single.state['index'], 0);
      expect(sessionStore.sessions.single.wordIds, <int>[1, 2]);

      // 销毁页面并释放控制器。
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test('listening directory rejects negative visual positioning', () {
    // 递归读取随身听页面和 widgets 子目录，避免拆分文件后绕过布局规则。
    final sourceFiles = Directory('lib/pages/listening')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    // 把全部 Dart 文件连接成一份文本，类似 PHP 测试批量审计模板目录。
    final source = sourceFiles
        .map((file) => file.readAsStringSync())
        .join('\n');
    // 四个 Positioned 方向属性都不允许使用负数把控件推出父级边界。
    expect(RegExp(r'(top|right|bottom|left):\s*-').hasMatch(source), isFalse);
    // Offset 负数属于依赖当前图标画布的人工补偿，同样禁止重新引入。
    expect(RegExp(r'Offset\(\s*-').hasMatch(source), isFalse);
    // Transform.translate 会绕过正常布局约束，本页面不应再使用。
    expect(source.contains('Transform.translate'), isFalse);
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
