// dart:io 读取页面源码，用回归测试禁止重新加入负数视觉定位。
import 'dart:io';

// material.dart 提供测试外层 MaterialApp。
import 'package:flutter/material.dart';
// flutter_test 提供 Widget 测试驱动与断言。
import 'package:flutter_test/flutter_test.dart';

// AppTheme 提供全站统一的字号、字重与颜色槽位。
import 'package:my_english/common/theme.dart';
// Tabler 图标用于确认播放状态没有回退成文字符号。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入单词、会话模型与进度出口。
import 'package:my_english/models/session.dart';
import 'package:my_english/models/session_record.dart';
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';
// 引入随身听页面。
import 'package:my_english/pages/listening/listening_page.dart';
// 引入随身听布局尺寸，用与生产代码相同的标准核对圆角。
import 'package:my_english/pages/listening/widgets/listening_layout.dart';
// 引入音频接口与设置（口音、释义分隔符、播放偏好都在设置表）。
import 'package:my_english/services/word_audio.dart';
import 'package:my_english/pages/review/services/session_progress.dart';
import 'package:my_english/store/settings.dart';

// 测试用内存会话 Store。
import '../../support/memory_session_store.dart';

///
/// 注册随身听页面的布局、播放和恢复交互测试。
void main() {
  testWidgets('listening page mirrors player layout and reveal interaction', (
    tester,
  ) async {
    final audio = _ImmediateAudioPlayer();
    // 2.0 起播放偏好（含释义分隔符）全部住在设置表。
    final settings = SettingsStore.inMemory();
    await settings.setDefinitionSeparator(DefinitionSeparator.fullWidthComma);
    await tester.pumpWidget(
      MaterialApp(
        // 必须装上真实主题：页面里的字号、字重、文字色统一从主题的 TextTheme
        // 槽位取，缺了它读到的会是 Material 自带的默认字号。
        theme: AppTheme.light,
        home: ListeningPage(
          words: _words,
          audioPlayer: audio,
          settings: settings,
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
      find.byKey(const Key('listening-pos-101')),
    );
    final hiddenDefinitionRect = tester.getRect(
      find.byKey(const Key('listening-definition-101')),
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
      tester.getRect(find.byKey(const Key('listening-pos-101'))),
      hiddenPosRect,
    );
    expect(
      tester.getRect(find.byKey(const Key('listening-definition-101'))),
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
    // 同一词性的中文定义使用设置的分隔符连接在一个 Text 中（此处为全角逗号）。
    expect(find.text('能力，才能'), findsOneWidget);
    expect(find.text('能力'), findsNothing);
    expect(find.text('才能'), findsNothing);
    expect(find.byIcon(TablerIcons.eye), findsOneWidget);

    // 返回按钮的点击区域仍从页面留白那一档开始。
    expect(
      tester.getTopLeft(find.byKey(const Key('close-listening'))).dx,
      closeTo(ListeningLayout.pageInset, 0.01),
    );
    // 箭头画布通过 Align 直接对齐按钮左边，不再使用 Transform 或负数偏移。
    expect(
      tester.getTopLeft(find.byIcon(TablerIcons.chevronLeft)).dx,
      closeTo(ListeningLayout.pageInset, 0.01),
    );
    // 设置图标的可见画布保持贴齐右侧同一档边距。
    expect(
      // getBottomRight(...).dx 就是可见设置图标最右侧的横坐标。
      tester.getBottomRight(find.byIcon(TablerIcons.settings)).dx,
      // 800 是 flutter_test 的默认画布宽度，减去一档页面留白就是目标右边缘。
      closeTo(800 - ListeningLayout.pageInset, 0.01),
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
    // “完成”的可见文字应贴齐面板右边距那一档，不能被按钮默认内边距向左推。
    // 桌面测试会限制底部面板宽度，因此先读取面板自身的最右侧坐标。
    final settingsSheetRight = tester
        .getBottomRight(find.byKey(const Key('listening-settings-sheet')))
        .dx;
    expect(
      // 从面板右边缘减去设计约定的那一档留白，就是“完成”文字的目标右边缘。
      tester
          .getBottomRight(find.byKey(const Key('listening-settings-done')))
          .dx,
      closeTo(settingsSheetRight - ListeningLayout.pageInset, 0.01),
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
    final words = <Word>[
      Word(
        spelling: 'layout',
        meanings: const <Meaning>[
          Meaning(
            id: 201,
            pos: 'n.',
            definition: '布局以及一段足够长的中文释义，用来确认窄屏幕中换行后的真实高度也会在骨架状态提前保留',
          ),
          Meaning(id: 202, pos: 'v.', definition: '安排'),
        ],
      ),
    ];
    // 注入立即完成的播放器，测试只关注答案卡布局。
    await tester.pumpWidget(
      MaterialApp(
        // 必须装上真实主题：页面里的字号、字重、文字色统一从主题的 TextTheme
        // 槽位取，缺了它读到的会是 Material 自带的默认字号。
        theme: AppTheme.light,
        home: ListeningPage(
          words: words,
          audioPlayer: _ImmediateAudioPlayer(),
          settings: SettingsStore.inMemory(),
        ),
      ),
    );
    await tester.pump();

    // 保存骨架态第一条释义槽位和第二条词性的坐标。
    final hiddenDefinitionRect = tester.getRect(
      find.byKey(const Key('listening-definition-201')),
    );
    final hiddenSecondPosRect = tester.getRect(
      find.byKey(const Key('listening-pos-202')),
    );
    // 按住答案卡切换成真实的多行释义。
    final peekGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('listening-answer-card'))),
    );
    await tester.pump();

    // 第一条释义槽位高度和第二条词性位置必须逐像素保持不变。
    expect(
      tester.getRect(find.byKey(const Key('listening-definition-201'))),
      hiddenDefinitionRect,
    );
    expect(
      tester.getRect(find.byKey(const Key('listening-pos-202'))),
      hiddenSecondPosRect,
    );

    // 主动抬起手指并销毁页面，确保播放计时器一并清理。
    await peekGesture.up();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('listening restores the persisted playback position', (
    tester,
  ) async {
    // 历史会话停在第二个词（cursor=1），展开释义偏好来自设置表。
    final store = MemorySessionStore();
    final settings = SettingsStore.inMemory();
    await settings.setListeningRevealAll(true);
    final session = Session(
      id: 1,
      module: ReviewModule.listening,
      kind: SessionKind.daily,
      status: SessionStatus.active,
      wordSetId: 1,
      items: const <int>[1, 2],
      cursor: 1,
      elapsed: 0,
      date: '2026-08-29',
      createdAt: DateTime.now(),
    );
    final progress = SessionProgress(
      store: store,
      session: session,
      records: const <SessionRecord>[],
    );
    await tester.pumpWidget(
      MaterialApp(
        // 必须装上真实主题：页面里的字号、字重、文字色统一从主题的 TextTheme
        // 槽位取，缺了它读到的会是 Material 自带的默认字号。
        theme: AppTheme.light,
        home: ListeningPage(
          words: _words,
          audioPlayer: _ImmediateAudioPlayer(),
          settings: settings,
          progress: progress,
        ),
      ),
    );
    await tester.pump();

    // 首帧直接停在第二个词，且展开释义偏好已生效。
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.byIcon(TablerIcons.eye), findsOneWidget);
    // 进入页面即保存一次「播到第几个」。
    expect(store.progressWrites, isNotEmpty);
    expect(store.progressWrites.last.cursor, 1);

    // 主动回到上一个词后，页面立即把新下标保存进会话。
    await tester.tap(find.text('上一个'));
    await tester.pump();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(store.progressWrites.last.cursor, 0);

    // 销毁页面并释放控制器。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('listening directory rejects negative visual positioning', () {
    // 递归读取随身听页面和 widgets 子目录，避免拆分文件后绕过布局规则。
    final sourceFiles = Directory('lib/pages/listening')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    // 把全部 Dart 文件连接成一份文本，统一做批量文本检查。
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

///
/// 随身听测试共用的固定单词列表。
final _words = <Word>[
  Word(
    id: 1,
    spelling: 'ability',
    meanings: const <Meaning>[
      Meaning(id: 101, pos: 'n.', definition: '能力'),
      Meaning(id: 102, pos: 'n.', definition: '才能'),
    ],
  ),
  Word(id: 2, spelling: 'abandon'),
];

///
/// 立即完成的播放器让测试无需网络和原生 MediaPlayer。
///
class _ImmediateAudioPlayer extends WordAudioPlayer {
  ///
  /// 立即完成指定单词的模拟播放。
  @override
  Future<void> play(String spelling, PronunciationAccent accent) async {}

  ///
  /// 立即完成模拟停止操作。
  @override
  Future<void> stop() async {}
}
