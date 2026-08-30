// dart:async 提供 Completer，用于模拟"发音请求挂起、可被新请求打断"的异步行为。
import 'dart:async';
// material.dart 提供 MaterialApp 与 SizedBox。
import 'package:flutter/material.dart';
// services.dart 提供 MethodChannel 与 MethodCall，用来观察听音辨义记录何时提交。
import 'package:flutter/services.dart';
// flutter_test 提供页面交互和断言。
import 'package:flutter_test/flutter_test.dart';
// Tabler 图标用于核对完成状态图标规范。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入设计令牌，核对播放和下一题的蓝色背景。
import 'package:my_english/common/theme.dart';
// 引入数据模型。
import 'package:my_english/models/session.dart';
import 'package:my_english/models/session_record.dart';
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';
// 引入听音辨义页面、进度出口与音频接口。
import 'package:my_english/pages/listening_meaning/listening_meaning_page.dart';
import 'package:my_english/pages/review/services/session_progress.dart';
// 引入听音辨义布局尺寸，使测试与真实页面共用同一组对齐标准。
import 'package:my_english/pages/listening_meaning/widgets/listening_meaning_layout.dart';
import 'package:my_english/services/word_audio.dart';
import 'package:my_english/store/settings.dart';

// 测试用内存会话 Store。
import '../../support/memory_session_store.dart';

///
/// 注册听音辨义页面的答题、播放、缓存和恢复交互测试。
///
///
///
/// 原生 addReviewRecord 事务结束后回传的结果。
///
/// 页面拿到它才允许切题；返回 null 会被 Store 判定成协议错误。
/// 具体数值不影响任何断言，测试只关心「写了没写、参数对不对」。
Map<String, Object?> _recordResult() => <String, Object?>{
  'streak': 1,
  'is_correct': true,
  'difficulty_before': 0,
  'difficulty_after': 0,
  'reviewed_at_before': 0,
  'reviewed_at_after': 1,
};

void main() {
  // Widget 测试需要先初始化二进制消息桥，才能为原生记录通道安装测试桩。
  TestWidgetsFlutterBinding.ensureInitialized();
  // 普通页面用例走正式通道名，但统一由空实现接住，避免访问真实 Android。
  const defaultRecordChannel = MethodChannel('my_english/word_store');
  // 保存测试环境提供的消息桥，后续每个用例都复用它注册处理器。
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // 每个用例开始前安装成功返回的默认记录通道。
  setUp(() {
    messenger.setMockMethodCallHandler(
      defaultRecordChannel,
      // 写记录的方法必须返回结果 Map，其余方法（如候选缓存）返回 null 即可。
      (call) async => call.method == 'addReviewRecord' ? _recordResult() : null,
    );
  });

  // 每个用例结束后注销处理器，避免影响其他测试文件。
  tearDown(() {
    messenger.setMockMethodCallHandler(defaultRecordChannel, null);
  });

  testWidgets('listeningMeaning handles wrong answers and advances between words', (
    tester,
  ) async {
    // 本轮会话只有 ability（带两条释义）和 abandon（无释义）两个单词：
    // 释义题的混淆项只能来自词库中“其他单词的含义”，而 abandon 没有释义，
    // 因此 ability 的释义题在纯随机且“不强行凑齐”的新规则下只剩一个正确选项。
    // 这正是用户拍板的降级行为：词库太小就不补，避免无中生有造含义词。
    await tester.pumpWidget(
      MaterialApp(
        home: ListeningMeaningPage(
          words: _words,
          audioPlayer: _ImmediateAudioPlayer(),
          accent: PronunciationAccent.american,
          progress: _freshProgress(),
        ),
      ),
    );
    await tester.pump();

    // 首题先显示拼写选择阶段和完整四个选项。
    expect(find.text('听音，选出正确的单词'), findsOneWidget);
    expect(find.text('ability'), findsOneWidget);
    // 中部单词卡按 ability 的七个字母建立七个独立占位槽，初始均为空。
    _expectTiles(tester, spelling: 'ability', revealedLetterCount: 0);
    // 每个拼写或释义小题都必须精确显示四个候选项。
    _expectFourOptions(tester);
    // 播放按钮已下线：重播交给单词卡听音钮，底部候选区改为文档流一行两个。
    // 四个候选两两一行、上下两行，同一行的两个卡片顶对齐。
    final row1Left = tester.getRect(
      find.byKey(const Key('listening-meaning-option-0')),
    );
    final row1Right = tester.getRect(
      find.byKey(const Key('listening-meaning-option-1')),
    );
    expect(row1Left.top, closeTo(row1Right.top, 0.01));
    final row2Left = tester.getRect(
      find.byKey(const Key('listening-meaning-option-2')),
    );
    final row2Right = tester.getRect(
      find.byKey(const Key('listening-meaning-option-3')),
    );
    expect(row2Left.top, closeTo(row2Right.top, 0.01));
    // 第二行整体在下方，说明候选按文档流纵向排列且一行两个。

    // 固定生成的交换字母干扰项应触发红色错误反馈且累计一次。
    await tester.tap(find.text('abliity'));
    await tester.pump();
    // 选错后以"答错 · 难度将 +1"提示，与新版难度告警横幅口径一致。
    expect(find.text('答错 · 难度将 +1'), findsOneWidget);
    // 新版原型只用红色文字反馈错误，不额外绘制错误图标。
    expect(find.byIcon(TablerIcons.x), findsNothing);

    // 正确拼写进入第一个词义的第一条释义。
    await tester.tap(find.text('ability'));
    // 正确作答会触发候选组整组过渡动画（AnimatedSwitcher），需等待动画结束再断言候选数量。
    await tester.pumpAndSettle();
    expect(find.text('n. · 选择释义 1/2'), findsOneWidget);
    // 词库只有 abandon 一个“其他单词”且它没有释义，语义题候选中只有正确答案自己；
    // 纯随机规则下不让凑齐混淆项，因此这里不再有四选一，而是单选项。
    await _expectSingleOption(tester, '能力');
    await tester.tap(find.text('能力'));
    // 同上：释义切换也触发候选组过渡，等待动画结束。
    await tester.pumpAndSettle();
    expect(find.text('n. · 选择释义 2/2'), findsOneWidget);
    await _expectSingleOption(tester, '才能');
    await tester.tap(find.text('才能'));
    await tester.pump();

    // 当前单词全部答对后仍留在 ability，不能自动跳到第二题。
    expect(find.text('当前单词已完成'), findsOneWidget);
    // 完成拼写后仍使用原来的七个瓷砖，只把全部真实字母填入，不改变卡片尺寸。
    _expectTiles(tester, spelling: 'ability', revealedLetterCount: 7);
    // 步骤一次性列出：第一步“听音选词”已完成，第二条是该词性的释义。
    expect(find.byKey(const Key('listening-meaning-step-word')), findsOneWidget);
    expect(find.byKey(const Key('listening-meaning-step-meaning-0')), findsOneWidget);
    // 释义步骤展示小写词性标签与已答出的两条释义 chips。
    expect(find.text('n.'), findsOneWidget);
    expect(find.text('能力'), findsOneWidget);
    expect(find.text('才能'), findsOneWidget);
    // 四个候选、提示和播放整组隐藏。
    _expectNoOptions(tester);
    expect(find.byKey(const Key('listening-meaning-hint')), findsNothing);
    expect(find.byKey(const Key('listening-meaning-play')), findsNothing);
    // 底部显示「再试一次 + 下一题」两个按钮。
    final retryButtonFinder = find.byKey(const Key('retry-listening-meaning-word'));
    final nextButtonFinder = find.byKey(const Key('next-listening-meaning-word'));
    expect(retryButtonFinder, findsOneWidget);
    expect(nextButtonFinder, findsOneWidget);
    expect(find.text('再试一次'), findsOneWidget);
    expect(find.text('下一题'), findsOneWidget);
    // 错误提示：本题选错过 1 次，完成后在「再试一次 / 下一题」上方展示累计错次
    // （不再显示旧的“难度将 +1”，且不再是完成有错就什么都不提示）。
    expect(find.text('本题已答错 1 次'), findsOneWidget);
    // 右侧主操作仍保持蓝色实心。
    final nextButton = tester.widget<FilledButton>(nextButtonFinder);
    expect(
      nextButton.style?.backgroundColor?.resolve(const <WidgetState>{}),
      AppTokens.accent,
    );
    // 两个按钮各占一半宽度，中间留出统一间距。
    final nextAreaWidth = tester
        .getSize(find.byKey(const Key('listening-meaning-next-area')))
        .width;
    // 去掉左右各 20 像素页面留白后，才是两个按钮可用的内容宽度。
    final contentWidth = nextAreaWidth - ListeningMeaningLayout.pageInset * 2;
    // 每个按钮 = （内容宽 - 中间间距）/ 2。
    final halfWidth = (contentWidth - ListeningMeaningLayout.columnGap) / 2;
    expect(tester.getSize(retryButtonFinder).width, closeTo(halfWidth, 0.01));
    expect(tester.getSize(nextButtonFinder).width, closeTo(halfWidth, 0.01));
    // 左按钮的右边界 + 间距 = 右按钮的左边界，保证中间确实留有空隙。
    final retryRect = tester.getRect(retryButtonFinder);
    final nextRect = tester.getRect(nextButtonFinder);
    expect(
      nextRect.left,
      closeTo(retryRect.right + ListeningMeaningLayout.columnGap, 0.01),
    );
    // 两个按钮上下边界完全一致。
    expect(retryRect.top, closeTo(nextRect.top, 0.01));
    expect(retryRect.height, ListeningMeaningLayout.actionHeight);
    expect(nextRect.height, ListeningMeaningLayout.actionHeight);

    // 只有点击长条按钮后才按首页列表顺序进入第二个单词。
    await tester.tap(nextButtonFinder);
    await tester.pumpAndSettle();
    expect(find.text('听音，选出正确的单词'), findsOneWidget);
    _expectFourOptions(tester);
    // 第二个单词没有释义，答对拼写后显示进入状态页的“完成”按钮。
    await tester.tap(find.text('abandon'));
    await tester.pump();
    _expectNoOptions(tester);
    expect(find.text('完成'), findsOneWidget);
    // 末题提交成功后进入原有完成状态页，并保留整轮错选统计。
    await tester.tap(find.byKey(const Key('next-listening-meaning-word')));
    await tester.pumpAndSettle();
    expect(find.text('听音辨义完成'), findsOneWidget);
    expect(find.text('共 2 个单词 · 答错 1 次'), findsOneWidget);
    expect(find.byIcon(TablerIcons.check), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 记录必须等到点击“下一题”才写入；事务未完成前页面保持原题且按钮锁定。
  testWidgets('completion is recorded only after tapping next', (tester) async {
    // 用内存 Store 记下实际结算的单词，取代已下线的 addReviewRecord 通道。
    final store = MemorySessionStore();
    await tester.pumpWidget(
      MaterialApp(
        home: ListeningMeaningPage(
          words: _words,
          audioPlayer: _ImmediateAudioPlayer(),
          accent: PronunciationAccent.american,
          progress: _freshProgress(store: store),
        ),
      ),
    );
    await tester.pump();

    // 选错一次制造非零错误计数，再完整答完当前单词。
    // 新原型没有提示按钮，错误计数改由原生按点错次数判定。
    await tester.tap(find.text('abliity'));
    await tester.pump();
    // 完整答完当前单词，但此时绝不能调用原生记录事务。
    await tester.tap(find.text('ability'));
    await tester.pump();
    await tester.tap(find.text('能力'));
    await tester.pump();
    await tester.tap(find.text('才能'));
    await tester.pump();
    expect(find.text('当前单词已完成'), findsOneWidget);
    // 结算必须只在点击「下一题」后发生；此时 Store 里一条结算记录都没有。
    expect(store.settles, isEmpty);

    // 点击下一题才把当前词结算落库。
    await tester.tap(find.byKey(const Key('next-listening-meaning-word')));
    await tester.pumpAndSettle();
    // 结算参数：本局会话 1、单词 ability(1)、普通练习照常推进复习时间。
    expect(store.settles, hasLength(1));
    expect(store.settles.first, (sessionId: 1, wordId: 1, updateReviewedAt: true));
    // 结算完成后才切换到下一个单词。
    expect(find.text('听音，选出正确的单词'), findsOneWidget);
    expect(find.text('abandon'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 最后一题同样先提交；提交成功后进入完成状态页，再返回首页并带回已复习 id。
  testWidgets('last completion submits before opening the done page', (
    tester,
  ) async {
    // 用内存 Store 记录最后一题的结算，取代已下线的 addReviewRecord 通道。
    final store = MemorySessionStore();
    // 接收听音辨义页通过 Navigator.pop 带回的单词 id。
    List<int>? returnedWordIds;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              // 首页先 push 听音辨义页，等待最后一题直接 pop 回来的结果。
              returnedWordIds = await Navigator.push<List<int>>(
                context,
                MaterialPageRoute<List<int>>(
                  builder: (_) => ListeningMeaningPage(
                    words: _words.skip(1).toList(),
                    audioPlayer: _ImmediateAudioPlayer(),
                    accent: PronunciationAccent.american,
                    progress: _freshProgress(store: store),
                            ),
                ),
              );
            },
            child: const Text('开始听音辨义'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开始听音辨义'));
    await tester.pumpAndSettle();

    // 答完最后一个词只进入当前题完成态，不点击就不提交、也不进入状态页。
    await tester.tap(find.text('abandon'));
    await tester.pump();
    expect(store.settles, isEmpty);
    expect(find.byType(ListeningMeaningPage), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('听音辨义完成'), findsNothing);

    // 点击完成后先结算一次，再进入原有的听音辨义完成状态页。
    await tester.tap(find.byKey(const Key('next-listening-meaning-word')));
    await tester.pumpAndSettle();
    expect(store.settles, hasLength(1));
    expect(store.settles.first, (sessionId: 1, wordId: 2, updateReviewedAt: true));
    expect(find.byType(ListeningMeaningPage), findsOneWidget);
    expect(find.text('听音辨义完成'), findsOneWidget);
    expect(find.text('共 1 个单词 · 答错 0 次'), findsOneWidget);
    expect(returnedWordIds, isNull);

    // 状态页点击返回后才 pop 到首页，并把已提交的单词 id 交回去。
    await tester.tap(find.byKey(const Key('finish-listeningMeaning')));
    await tester.pumpAndSettle();
    expect(find.byType(ListeningMeaningPage), findsNothing);
    expect(find.text('开始听音辨义'), findsOneWidget);
    expect(returnedWordIds, <int>[2]);
  });

  // 「再试一次」必须把当前单词退回到刚进入这一题的样子：
  // 拼写没选、释义没选、提示收起、错项清空，底部重新出现四选一与提示/播放。
  testWidgets('retry button resets the current word to its initial state', (
    tester,
  ) async {
    // 只放一个带释义的单词，便于验证释义步骤也一起回滚。
    await tester.pumpWidget(
      MaterialApp(
        home: ListeningMeaningPage(
          words: _words.take(1).toList(),
          audioPlayer: _ImmediateAudioPlayer(),
          accent: PronunciationAccent.american,
          progress: _freshProgress(),
        ),
      ),
    );
    await tester.pump();

    // 先选错一次制造「非初始状态」：错误选项进入红色禁用态。
    await tester.tap(find.text('abliity'));
    await tester.pump();
    expect(find.text('答错 · 难度将 +1'), findsOneWidget);

    // 完整答对拼写与两条释义，进入完成态。
    await tester.tap(find.text('ability'));
    await tester.pump();
    await tester.tap(find.text('能力'));
    await tester.pump();
    await tester.tap(find.text('才能'));
    await tester.pump();
    expect(find.text('当前单词已完成'), findsOneWidget);

    // 点击「再试一次」。
    await tester.tap(find.byKey(const Key('retry-listening-meaning-word')));
    await tester.pump();

    // 回到拼写阶段：四个候选项按一行两个重新出现。
    expect(find.text('听音，选出正确的单词'), findsOneWidget);
    expect(find.text('当前单词已完成'), findsNothing);
    _expectFourOptions(tester);
    // 底部候选区回到文档流、一行两个。
    expect(
      find.byKey(const Key('listening-meaning-bottom-controls')),
      findsOneWidget,
    );
    // 完成态的两个按钮消失。
    expect(find.byKey(const Key('retry-listening-meaning-word')), findsNothing);
    expect(find.byKey(const Key('next-listening-meaning-word')), findsNothing);
    // 回到一开始的样子，字母槽重新全空。
    _expectTiles(tester, spelling: 'ability', revealedLetterCount: 0);
    // 上一次答出的释义 chips 不再显示（步骤回到未答状态）。
    expect(find.text('才能'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 回归：答对后的"奖励发音"还在播时点下一题，新单词必须能正常发音。
  // 旧实现里 _isPlaying 为 true 会让新播放请求被直接吞掉，新题永远不出声。
  testWidgets('next word interrupts the pending reward audio', (tester) async {
    // 这个假播放器的 play 会一直挂起，模拟"音频还没播完"。
    final player = _PendingAudioPlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: ListeningMeaningPage(
          words: _words,
          audioPlayer: player,
          accent: PronunciationAccent.american,
          progress: _freshProgress(),
        ),
      ),
    );
    await tester.pump();

    // 进入页面自动播放第一个单词，且这次播放一直没有结束。
    expect(player.requested, <String>['ability']);

    // 答对拼写与两条释义 → 触发一次奖励发音（第二次请求，仍是 ability）。
    await tester.tap(find.text('ability'));
    await tester.pump();
    await tester.tap(find.text('能力'));
    await tester.pump();
    await tester.tap(find.text('才能'));
    await tester.pump();
    expect(player.requested, <String>['ability', 'ability']);

    // 奖励音频尚未结束时点下一题。
    await tester.tap(find.byKey(const Key('next-listening-meaning-word')));
    await tester.pump();

    // 关键断言：新单词的发音请求必须真的发出去，而不是被"正在播放"挡掉。
    expect(player.requested, <String>['ability', 'ability', 'abandon']);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 【已下线】原版「提示逐步揭示开头字母」功能在 2.0 会话模型中移除：提示按钮
  // 不再存在，只剩答对后整词揭示一种情况（见 listening_meaning_question_content.dart）。
  // 相关用例（hint reveals leading letters progressively）已随功能一起删除。
  testWidgets('question overlay replays without intercepting bottom controls', (
    tester,
  ) async {
    // 使用真实手机比例，避免测试框架默认矮屏把 Steps 中点压到底部候选区后面。
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // 立即完成的记录播放器可以精确统计每一次播放请求。
    final player = _RecordingAudioPlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: ListeningMeaningPage(
          words: _words,
          audioPlayer: player,
          accent: PronunciationAccent.american,
          progress: _freshProgress(),
        ),
      ),
    );
    await tester.pump();
    // 进入页面会先自动播放一次。
    expect(player.requested, <String>['ability']);
    // 新透明命中层必须覆盖顶部区域以下的完整第二部分，而非只包住提示和 Steps。
    final overlayRect = tester.getRect(
      find.byKey(const Key('listening-meaning-question-audio-overlay')),
    );
    final questionStackRect = tester.getRect(
      find.byKey(const Key('listening-meaning-question-stack')),
    );
    expect(overlayRect, questionStackRect);

    // 点击提示横幅中心，事件应由外层中部播放热区接收。
    final promptCenter = tester
        .getRect(find.byKey(const Key('listening-meaning-prompt-information')))
        .center;
    await tester.tapAt(promptCenter);
    await tester.pump();
    expect(player.requested, <String>['ability', 'ability']);
    // 点击 Steps 轨道中心同样重播，不必伸手去够右下角按钮。
    final stepsCenter = tester
        .getRect(find.byKey(const Key('listening-meaning-vertical-steps')))
        .center;
    await tester.tapAt(stepsCenter);
    await tester.pump();
    expect(player.requested, <String>['ability', 'ability', 'ability']);

    // 单词卡自身的听音按钮位于透明层内部，子按钮应赢得事件且只播放一次。
    await tester.tap(find.byKey(const Key('listening-meaning-word-card-speaker')));
    await tester.pump();
    expect(player.requested, <String>[
      'ability',
      'ability',
      'ability',
      'ability',
    ]);

    // 候选区改到文档流底部之后，它已不在透明覆盖层内部，而是整体位于其下方：
    // 底部操作区与题目热区分属 Column 上下两个兄弟区域，天然不再需要"谁拦截谁"。
    final controlsRect = tester.getRect(
      find.byKey(const Key('listening-meaning-bottom-controls')),
    );
    // 覆盖层顶到题区，候选区从题区之下才开始，二者不重叠。
    expect(overlayRect.bottom, lessThanOrEqualTo(controlsRect.top + 0.01));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('question overlay keeps long content vertically scrollable', (
    tester,
  ) async {
    // 使用较矮手机画布和多条释义，确保 Steps 内容真实超过透明层可视高度。
    await tester.binding.setSurfaceSize(const Size(390, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final longWord = Word(
      id: 30,
      spelling: 'scroll',
      meanings: const <Meaning>[
        Meaning(id: 301, pos: 'n.', definition: '释义一'),
        Meaning(id: 302, pos: 'v.', definition: '释义二'),
        Meaning(id: 303, pos: 'adj.', definition: '释义三'),
        Meaning(id: 304, pos: 'adv.', definition: '释义四'),
        Meaning(id: 305, pos: 'prep.', definition: '释义五'),
        Meaning(id: 306, pos: 'conj.', definition: '释义六'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ListeningMeaningPage(
          words: <Word>[longWord],
          audioPlayer: _ImmediateAudioPlayer(),
          accent: PronunciationAccent.american,
          progress: _freshProgress(),
        ),
      ),
    );
    await tester.pump();

    // 保存拖动前单词卡位置；手势从内容区发起，不能落在悬浮候选按钮上。
    final beforeTop = tester
        .getTopLeft(find.byKey(const Key('listening-meaning-word-card')))
        .dy;
    final overlayRect = tester.getRect(
      find.byKey(const Key('listening-meaning-question-audio-overlay')),
    );
    await tester.dragFrom(
      Offset(overlayRect.center.dx, overlayRect.top + 120),
      const Offset(0, -160),
    );
    await tester.pumpAndSettle();

    // ScrollView 必须消费纵向拖动，证明透明播放层没有封死原有滚动能力。
    final afterTop = tester
        .getTopLeft(find.byKey(const Key('listening-meaning-word-card')))
        .dy;
    expect(afterTop, lessThan(beforeTop));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('candidate options are unique and never duplicate the answer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ListeningMeaningPage(
          words: _words.take(1).toList(),
          audioPlayer: _ImmediateAudioPlayer(),
          accent: PronunciationAccent.american,
          progress: _freshProgress(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 新局生成四个互不重复（忽略大小写）的候选，且正确答案必定在场。
    final options = _visibleOptionTexts(tester);
    expect(options, hasLength(4));
    expect(options.map((text) => text.toLowerCase()).toSet(), hasLength(4));
    expect(options, contains('ability'));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('continue mode resumes into the definition stage after spelling', (
    tester,
  ) async {
    // ability 的拼写那一步已经答对（含义为空的答对记录）。
    final progress = _freshProgress(
      cursor: 0,
      records: const <SessionRecord>[
        SessionRecord(id: 1, wordId: 1, meaningId: null, input: 'ability', isCorrect: true),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ListeningMeaningPage(
          words: _words.take(1).toList(),
          audioPlayer: _ImmediateAudioPlayer(),
          accent: PronunciationAccent.american,
          progress: progress,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 直接进入释义阶段：第一条释义「能力」出现，不再要求重选拼写。
    expect(find.text('能力'), findsWidgets);
    // 释义阶段的候选项是中文，正确答案拼写不出现在四选一里。
    expect(_visibleOptionTexts(tester), isNot(contains('ability')));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('continue mode restores elapsed from session and keeps counting', (tester) async {
    // 用户此前花了 125 秒退出，重进后右上角计时器必须接着累计，
    // 不能每次进入都从 0 开始计时。
    final progress = _freshProgress(elapsed: 125);
    await tester.pumpWidget(
      MaterialApp(
        home: ListeningMeaningPage(
          words: _words,
          audioPlayer: _ImmediateAudioPlayer(),
          accent: PronunciationAccent.american,
          progress: progress,
        ),
      ),
    );
    await tester.pump();

    // 恢复后显示 02:05，而不是从 00:00 开始。
    expect(
      tester.widget<Text>(find.byKey(const Key('listening-meaning-elapsed'))).data,
      '02:05',
    );

    // 原地停留一秒，计时器继续从累计值上推进到 02:06。
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.widget<Text>(find.byKey(const Key('listening-meaning-elapsed'))).data,
      '02:06',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('candidate options are ordered by spelling ascending', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ListeningMeaningPage(
          words: _words,
          audioPlayer: _ImmediateAudioPlayer(),
          accent: PronunciationAccent.american,
          progress: _freshProgress(),
        ),
      ),
    );
    await tester.pump();

    // 四选一（三个干扰项 + 正确答案 ability）应忽略大小写按字母升序排，
    // 与看义选词、词义连连的候选口径统一；而不是固定在某个取模位上。
    final displayed = _visibleOptionTexts(tester);
    expect(displayed, hasLength(4));
    final sorted = [...displayed]..sort((first, second) {
        final byLetter = first.toLowerCase().compareTo(second.toLowerCase());
        return byLetter != 0 ? byLetter : first.compareTo(second);
      });
    expect(displayed, sorted);
    // 正确项只要在其中即可，身份不因排序丢失。
    expect(displayed, contains('ability'));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('listeningMeaning mirrors listening header and anchors split controls', (
    tester,
  ) async {
    // 使用真实手机比例的窄屏，同时验证右侧窄按钮不会溢出。
    await tester.binding.setSurfaceSize(const Size(390, 844));
    // 用例结束后恢复测试框架的默认屏幕，避免影响其他页面。
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // 模拟底部 24 像素系统手势区，检查 SafeArea 和页面留白是否同时生效。
    const safeBottom = 24.0;
    // MaterialApp 提供主题和路由环境，内层 MediaQuery 注入本用例需要的安全区。
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            padding: EdgeInsets.only(bottom: safeBottom),
          ),
          child: ListeningMeaningPage(
            words: _words,
            audioPlayer: _ImmediateAudioPlayer(),
            accent: PronunciationAccent.american,
            progress: _freshProgress(),
          ),
        ),
      ),
    );
    // 等待首帧布局与进入页面后的自动发音状态更新完成。
    await tester.pump();

    // 返回按钮画布与随身听一样，直接从 20 像素页面边距开始。
    final closeRect = tester.getRect(find.byKey(const Key('close-listeningMeaning')));
    expect(closeRect.left, ListeningMeaningLayout.pageInset);
    expect(closeRect.width, ListeningMeaningLayout.headerButtonSize);
    // 题号的水平中心必须和 390 像素屏幕的中心完全重合。
    final progressLabelRect = tester.getRect(
      find.byKey(const Key('listening-meaning-progress-label')),
    );
    expect(progressLabelRect.center.dx, closeTo(195, 0.01));
    // 进度条左右均保留 20 像素，高度与随身听相同。
    final progressBarRect = tester.getRect(
      find.byKey(const Key('listening-meaning-progress-bar')),
    );
    expect(progressBarRect.left, ListeningMeaningLayout.pageInset);
    expect(progressBarRect.right, 390 - ListeningMeaningLayout.pageInset);
    expect(progressBarRect.height, ListeningMeaningLayout.progressHeight);

    // 按下标从上到下读取四个候选词的真实边界。
    final optionRects = <Rect>[
      for (var index = 0; index < 4; index++)
        tester.getRect(find.byKey(Key('listening-meaning-option-$index'))),
    ];
    // 底部候选改为文档流一行两个：0/1 同顶成第一行，2/3 同顶成第二行。
    expect(optionRects[0].top, closeTo(optionRects[1].top, 0.01));
    expect(optionRects[2].top, closeTo(optionRects[3].top, 0.01));
    // 每行两卡片等宽，高度统一。
    for (final optionRect in optionRects) {
      expect(optionRect.height, ListeningMeaningLayout.optionHeight);
    }
    expect(optionRects[0].width, closeTo(optionRects[1].width, 0.01));
    expect(optionRects[2].width, closeTo(optionRects[3].width, 0.01));
    // 第二行顶部 = 第一行底部 + 行间距。
    expect(
      optionRects[2].top,
      closeTo(optionRects[0].bottom + ListeningMeaningLayout.optionGap, 0.01),
    );
    // 每行左侧都有固定灰色正方形 badge，文字依次为 A、B、C、D。
    for (var index = 0; index < optionRects.length; index += 1) {
      final badgeFinder = find.byKey(Key('listening-meaning-option-badge-$index'));
      final badgeRect = tester.getRect(badgeFinder);
      final labelRect = tester.getRect(
        find.byKey(Key('listening-meaning-option-label-$index')),
      );
      // 方形 badge 的宽高严格相等，并按统一内边距贴齐候选按钮左侧。
      expect(badgeRect.width, ListeningMeaningLayout.optionBadgeSize);
      expect(badgeRect.height, ListeningMeaningLayout.optionBadgeSize);
      expect(
        badgeRect.left,
        closeTo(
          // 边框绘制在按钮内容区外侧，实际内容从一像素边框之后开始。
          optionRects[index].left + 1 + ListeningMeaningLayout.optionHorizontalInset,
          0.01,
        ),
      );
      expect(
        find.descendant(of: badgeFinder, matching: find.text('ABCD'[index])),
        findsOneWidget,
      );
      // badge 不参与候选文本的居中计算，文字中心仍与整个按钮中心重合。
      expect(labelRect.center.dx, closeTo(optionRects[index].center.dx, 0.01));
    }

    // 播放按钮已下线；候选词一行两个，宽度 =（内容宽 − 行间距）/ 2。
    // 内容宽度 = 屏幕宽 − 左右两处页面留白。
    final contentWidth =
        390 - ListeningMeaningLayout.pageInset * 2;
    final halfWidth =
        (contentWidth - ListeningMeaningLayout.optionGap) / 2;
    expect(optionRects[0].width, closeTo(halfWidth, 0.01));
    expect(optionRects[1].left, closeTo(optionRects[0].right + ListeningMeaningLayout.optionGap, 0.01));
    // 候选区底部必须位于系统安全区和页面额外留白之上。
    expect(
      optionRects[2].bottom,
      closeTo(844 - safeBottom - ListeningMeaningLayout.bottomInset, 0.01),
    );

    // 中部三个子模块必须位于进度条和底部候选区之间，不能与两者重叠。
    final questionContentRect = tester.getRect(
      find.byKey(const Key('listening-meaning-question-content')),
    );
    expect(
      questionContentRect.top,
      closeTo(
        progressBarRect.bottom + ListeningMeaningLayout.questionVerticalInset,
        0.01,
      ),
    );
    expect(questionContentRect.bottom, lessThan(optionRects.first.top));
    // 三个同级模块按“单词卡、独立提示横幅、全量步骤”居上排列。
    final wordCardRect = tester.getRect(
      find.byKey(const Key('listening-meaning-word-card')),
    );
    final promptInformationRect = tester.getRect(
      find.byKey(const Key('listening-meaning-prompt-information')),
    );
    final stepsSectionRect = tester.getRect(
      find.byKey(const Key('listening-meaning-vertical-steps')),
    );
    final stageRect = tester.getRect(
      find.byKey(const Key('listening-meaning-stage-label')),
    );
    final feedbackRect = tester.getRect(
      find.byKey(const Key('listening-meaning-feedback-slot')),
    );
    expect(wordCardRect.top, questionContentRect.top);
    expect(promptInformationRect.top, greaterThan(wordCardRect.bottom));
    expect(stepsSectionRect.top, greaterThan(promptInformationRect.bottom));
    // 提示到全部步骤使用同一条 Tabler Steps vertical 轨道。
    expect(find.byKey(const Key('listening-meaning-vertical-steps')), findsOneWidget);
    final promptMarkerRect = tester.getRect(
      find.byKey(const Key('listening-meaning-step-marker-0')),
    );
    final meaningMarkerRect = tester.getRect(
      find.byKey(const Key('listening-meaning-step-marker-1')),
    );
    final connectorRect = tester.getRect(
      find.byKey(const Key('listening-meaning-step-connector-0')),
    );
    // 两个节点和连接线的水平中心一致，轨道不会左右折线。
    expect(
      promptMarkerRect.center.dx,
      closeTo(meaningMarkerRect.center.dx, 0.01),
    );
    expect(connectorRect.center.dx, closeTo(promptMarkerRect.center.dx, 0.01));
    // 连接线从听音节点下缘连续延伸到释义节点上缘。
    expect(connectorRect.top, closeTo(promptMarkerRect.bottom, 0.01));
    expect(connectorRect.bottom, closeTo(meaningMarkerRect.top, 0.01));
    // 提示与反馈都属于第二个模块（独立横幅），并按顶部阅读顺序排列。
    expect(stageRect.top, greaterThanOrEqualTo(promptInformationRect.top));
    expect(feedbackRect.top, greaterThan(stageRect.bottom));
    expect(
      feedbackRect.bottom,
      lessThanOrEqualTo(promptInformationRect.bottom),
    );
    expect(stepsSectionRect.bottom, questionContentRect.bottom);

    // 销毁页面以触发 dispose，使自动发音相关资源在用例结束前被停止。
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'listeningMeaning restores the second word and skips settled ones',
    (tester) async {
      final store = MemorySessionStore();
      // 词 1（ability）已完整答对：拼写 + 两条释义都写过记录。
      final progress = _freshProgress(
        store: store,
        cursor: 1,
        records: const <SessionRecord>[
          SessionRecord(id: 1, wordId: 1, meaningId: null, input: 'ability', isCorrect: true),
          SessionRecord(id: 2, wordId: 1, meaningId: 101, input: '能力', isCorrect: true),
          SessionRecord(id: 3, wordId: 1, meaningId: 102, input: '才能', isCorrect: true),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ListeningMeaningPage(
            words: _words,
            audioPlayer: _ImmediateAudioPlayer(),
            accent: PronunciationAccent.american,
            progress: progress,
          ),
        ),
      );
      await tester.pump();

      // 首帧直接停在第二个词（abandon，无释义 → 只有拼写阶段）。
      expect(find.text('2 / 2'), findsOneWidget);
      // 已答对的 ability 不会重复出题：候选里不再出现它的拼写。
      expect(_visibleOptionTexts(tester), isNot(contains('ability')));
      // 恢复阶段不会重复结算已答对的词。
      expect(store.settles, isEmpty);
      // 页面没有任何异常。
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

///
/// 断言当前小题始终存在精确四个候选项。
void _expectFourOptions(WidgetTester tester) {
  // 下标 0..3 都必须各有一个选项。
  for (var index = 0; index < 4; index++) {
    expect(find.byKey(Key('listening-meaning-option-$index')), findsOneWidget);
  }
  // 下标 4 不允许出现，以此排除意外生成第五项。
  expect(find.byKey(const Key('listening-meaning-option-4')), findsNothing);
}

///
/// 断言当前单词完成后四个候选项已经全部卸载。
void _expectNoOptions(WidgetTester tester) {
  // 逐个检查原四个固定下标。
  for (var index = 0; index < 4; index++) {
    expect(find.byKey(Key('listening-meaning-option-$index')), findsNothing);
  }
}

///
/// 断言语义题在“词库极小、凑不齐混淆项”时只渲染出唯一一个正确的释义选项。
///
/// 纯随机规则下不强行凑齐四选一：候选池为空时，页面只显示当前词自身那条
/// 释义（index 0），其余三个占位都不出现——这正是用户拍板的“不无中生有”行为。
Future<void> _expectSingleOption(WidgetTester tester, String correct) async {
  // 只有唯一选项，且文本就是正确答案本身。
  expect(find.byKey(const Key('listening-meaning-option-0')), findsOneWidget);
  expect(
    tester.widget<Text>(
      find.byKey(const Key('listening-meaning-option-label-0')),
    ).data,
    correct,
  );
  // 其余下标没有任何选项，绝不给正确答案补假混淆项。
  for (var index = 1; index < 4; index++) {
    expect(find.byKey(Key('listening-meaning-option-$index')), findsNothing);
  }
  // 等待候选组入场过渡结束，避免后续点击被动画状态卡住。
  await tester.pumpAndSettle();
}

///
/// 按 A/B/C/D 的页面顺序读取当前所有候选文本。
///
/// 候选数不再固定为 4：词库极小（只剩当前词）时，释义题可能只有正确答案一
/// 项，因此这里只收集实际渲染出来的候选，而不是假定一定有 4 个。
List<String> _visibleOptionTexts(WidgetTester tester) {
  // 文本组件拥有固定下标 Key，因此不受页面其他重复文字或语义节点影响。
  final texts = <String>[];
  for (var index = 0; index < 4; index += 1) {
    final finder = find.byKey(Key('listening-meaning-option-label-$index'));
    if (tester.any(finder)) {
      texts.add(tester.widget<Text>(finder).data!);
    }
  }
  return texts;
}

///
/// 断言一个英文字母严格对应一个固定瓷砖，并核对当前公开的字母数量。
void _expectTiles(
  WidgetTester tester, {
  required String spelling,
  required int revealedLetterCount,
}) {
  // 本测试数据都是普通英文单词，因此字符串下标与页面英文字母下标一致。
  for (var index = 0; index < spelling.length; index += 1) {
    // 每个字母必须存在独立字母瓷砖，不能退回一整串下划线文本。
    expect(find.byKey(Key('listening-meaning-tile-$index')), findsOneWidget);
    // 直接读取瓷砖内 Text 的值，避免页面其他候选词文本干扰断言。
    final letterText = tester.widget<Text>(
      find.byKey(Key('listening-meaning-tile-letter-$index')),
    );
    // 字母字号跟随布局常量，不能被后续局部样式意外覆盖。
    expect(letterText.style?.fontSize, ListeningMeaningLayout.wordLetterFontSize);
    // 提示范围以内显示大写真实字母，其余瓷砖保持空字符串。
    expect(
      letterText.data,
      index < revealedLetterCount ? spelling[index].toUpperCase() : '',
    );
  }
  // 单词长度之外不允许多出额外字母瓷砖。
  expect(find.byKey(Key('listening-meaning-tile-${spelling.length}')), findsNothing);
}

///
/// 听音辨义页面测试共用的固定单词列表。
final _words = <Word>[
  Word(
    id: 1,
    spelling: 'ability',
    difficulty: 3,
    meanings: const <Meaning>[
      Meaning(id: 101, pos: 'n.', definition: '能力'),
      Meaning(id: 102, pos: 'n.', definition: '才能'),
    ],
  ),
  Word(id: 2, spelling: 'abandon'),
];

///
/// 构造一局「进行中」的听音辨义会话与进度出口。
///
/// [cursor] 是上次保存的单词下标；[records] 用于续玩恢复现场。
///
/// [elapsed] 是本局已用秒数（来自上次保存的会话），用于验证恢复后题目页
/// 右上角计时器从累计值继续，而不是每次进入都从 0 开始。
SessionProgress _freshProgress({
  MemorySessionStore? store,
  int cursor = 0,
  int elapsed = 0,
  List<SessionRecord> records = const <SessionRecord>[],
}) => SessionProgress(
  store: store ?? MemorySessionStore(),
  session: Session(
    id: 1,
    module: ReviewModule.listeningMeaning,
    kind: SessionKind.daily,
    status: SessionStatus.active,
    wordSetId: 1,
    items: <int>[for (final word in _words) word.id!],
    cursor: cursor,
    elapsed: elapsed,
    date: '2026-08-25',
    createdAt: DateTime.now(),
  ),
  records: records,
);

///
/// 每次播放和停止都会立即完成的测试播放器。
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

///
/// 记录每次播放请求并立即结束，适合验证多个点击热区复用同一播放事件。
///
class _RecordingAudioPlayer extends WordAudioPlayer {
  ///
  /// 按发生顺序保存被请求播放的单词。
  final List<String> requested = <String>[];

  ///
  /// 记录指定单词后立即完成模拟播放。
  @override
  Future<void> play(String spelling, PronunciationAccent accent) async {
    // 每次调用都追加一次，不做去重。
    requested.add(spelling);
  }

  ///
  /// 立即完成模拟停止操作。
  @override
  Future<void> stop() async {}
}

///
/// 模拟真实原生播放器：play 的 Future 会一直挂起直到音频播完，
/// 新的 play 会把上一个请求以「已被替换」的中断异常结束（与 Android 实现一致）。
///
class _PendingAudioPlayer extends WordAudioPlayer {
  ///
  /// 依次记录每一次被请求播放的单词，供测试断言播放顺序。
  final List<String> requested = <String>[];

  ///
  /// 当前尚未结束的那次播放；Completer 相当于一个"手动兑现的 Promise"。
  Completer<void>? _pending;

  ///
  /// 记录新请求、中断旧请求并返回仍处于等待状态的播放结果。
  @override
  Future<void> play(String spelling, PronunciationAccent accent) {
    // 记录本次请求。
    requested.add(spelling);
    // 新请求到来时打断上一次，未完成的旧 Future 以中断异常结束。
    _completePending();
    // 本次播放挂起，不主动完成，模拟"音频正在播放中"。
    final completer = Completer<void>();
    _pending = completer;
    return completer.future;
  }

  ///
  /// 中断当前仍处于等待状态的模拟播放。
  @override
  Future<void> stop() async {
    // 停止同样让挂起的播放以中断异常收尾。
    _completePending();
  }

  ///
  /// 结束当前挂起的播放；页面会把这个异常当作"被替换"而静默忽略。
  void _completePending() {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const WordAudioInterruptedException());
    }
  }
}
