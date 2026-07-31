// dart:async 提供 Completer，用于模拟"发音请求挂起、可被新请求打断"的异步行为。
import 'dart:async';
// material.dart 提供 MaterialApp 与 SizedBox。
import 'package:flutter/material.dart';
// flutter_test 提供页面交互和断言。
import 'package:flutter_test/flutter_test.dart';
// Tabler 图标用于核对完成状态图标规范。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入设计令牌，核对播放和下一题的蓝色背景。
import 'package:my_english/common/theme.dart';
// 引入数据模型。
import 'package:my_english/models/meaning.dart';
import 'package:my_english/models/word.dart';
// 引入默写页面与音频接口。
import 'package:my_english/pages/dictation/dictation_page.dart';
// 引入默写布局尺寸，使测试与真实页面共用同一组对齐标准。
import 'package:my_english/pages/dictation/widgets/dictation_layout.dart';
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
    // 中部单词卡按 ability 的七个字母建立七个独立占位槽，初始均为空。
    _expectTiles(tester, spelling: 'ability', revealedLetterCount: 0);
    // 每个拼写或释义小题都必须精确显示四个候选项。
    _expectFourOptions(tester);
    // 播放是右侧主操作，使用蓝色背景和白色前景。
    final playButton = tester.widget<OutlinedButton>(
      find
          .descendant(
            of: find.byKey(const Key('dictation-play')),
            matching: find.byType(OutlinedButton),
          )
          .first,
    );
    expect(
      playButton.style?.backgroundColor?.resolve(const <WidgetState>{}),
      AppTokens.accent,
    );
    expect(
      playButton.style?.foregroundColor?.resolve(const <WidgetState>{}),
      Colors.white,
    );

    // 固定生成的交换字母干扰项应触发红色错误反馈且累计一次。
    await tester.tap(find.text('abliity'));
    await tester.pump();
    expect(find.text('不对，再试试'), findsOneWidget);
    // 新版原型只用红色文字反馈错误，不额外绘制错误图标。
    expect(find.byIcon(TablerIcons.x), findsNothing);

    // 正确拼写进入第一个词义的第一条释义。
    await tester.tap(find.text('ability'));
    await tester.pump();
    expect(find.text('N. · 选择释义 1/2'), findsOneWidget);
    _expectFourOptions(tester);
    await tester.tap(find.text('能力'));
    await tester.pump();
    expect(find.text('N. · 选择释义 2/2'), findsOneWidget);
    _expectFourOptions(tester);
    await tester.tap(find.text('才能'));
    await tester.pump();

    // 当前单词全部答对后仍留在 ability，不能自动跳到第二题。
    expect(find.text('当前单词已完成'), findsOneWidget);
    // 完成拼写后仍使用原来的七个瓷砖，只把全部真实字母填入，不改变卡片尺寸。
    _expectTiles(tester, spelling: 'ability', revealedLetterCount: 7);
    // 步骤一次性列出：第一步“听音选词”已完成，第二条是该词性的释义。
    expect(find.byKey(const Key('dictation-step-word')), findsOneWidget);
    expect(find.byKey(const Key('dictation-step-meaning-0')), findsOneWidget);
    // 释义步骤展示词性小标签与已答出的两条释义 chips（词性大写显示）。
    expect(find.text('N.'), findsOneWidget);
    expect(find.text('能力'), findsOneWidget);
    expect(find.text('才能'), findsOneWidget);
    // 四个候选、提示和播放整组隐藏。
    _expectNoOptions(tester);
    expect(find.byKey(const Key('dictation-hint')), findsNothing);
    expect(find.byKey(const Key('dictation-play')), findsNothing);
    // 底部显示「再试一次 + 下一题」两个按钮。
    final retryButtonFinder = find.byKey(const Key('retry-dictation-word'));
    final nextButtonFinder = find.byKey(const Key('next-dictation-word'));
    expect(retryButtonFinder, findsOneWidget);
    expect(nextButtonFinder, findsOneWidget);
    expect(find.text('再试一次'), findsOneWidget);
    expect(find.text('下一题'), findsOneWidget);
    // 右侧主操作仍保持蓝色实心。
    final nextButton = tester.widget<FilledButton>(nextButtonFinder);
    expect(
      nextButton.style?.backgroundColor?.resolve(const <WidgetState>{}),
      AppTokens.accent,
    );
    // 两个按钮各占一半宽度，中间留出统一间距。
    final nextAreaWidth = tester
        .getSize(find.byKey(const Key('dictation-next-area')))
        .width;
    // 去掉左右各 20 像素页面留白后，才是两个按钮可用的内容宽度。
    final contentWidth = nextAreaWidth - DictationLayout.pageInset * 2;
    // 每个按钮 = （内容宽 - 中间间距）/ 2。
    final halfWidth = (contentWidth - DictationLayout.columnGap) / 2;
    expect(tester.getSize(retryButtonFinder).width, closeTo(halfWidth, 0.01));
    expect(tester.getSize(nextButtonFinder).width, closeTo(halfWidth, 0.01));
    // 左按钮的右边界 + 间距 = 右按钮的左边界，保证中间确实留有空隙。
    final retryRect = tester.getRect(retryButtonFinder);
    final nextRect = tester.getRect(nextButtonFinder);
    expect(
      nextRect.left,
      closeTo(retryRect.right + DictationLayout.columnGap, 0.01),
    );
    // 两个按钮上下边界完全一致。
    expect(retryRect.top, closeTo(nextRect.top, 0.01));
    expect(retryRect.height, DictationLayout.actionHeight);
    expect(nextRect.height, DictationLayout.actionHeight);

    // 只有点击长条按钮后才按首页列表顺序进入第二个单词。
    await tester.tap(nextButtonFinder);
    await tester.pump();
    expect(find.text('听音，选出正确的单词'), findsOneWidget);
    _expectFourOptions(tester);
    // 第二个单词没有释义，答对拼写后改为最后的“完成”长条按钮。
    await tester.tap(find.text('abandon'));
    await tester.pump();
    _expectNoOptions(tester);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('默写完成'), findsNothing);
    // 点击最后一题的完成按钮后才进入整轮统计页。
    await tester.tap(find.byKey(const Key('next-dictation-word')));
    await tester.pump();
    expect(find.text('默写完成'), findsOneWidget);
    expect(find.text('共 2 个单词 · 答错 1 次'), findsOneWidget);
    expect(find.byIcon(TablerIcons.check), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // 「再试一次」必须把当前单词退回到刚进入这一题的样子：
  // 拼写没选、释义没选、提示收起、错项清空，底部重新出现四选一与提示/播放。
  testWidgets('retry button resets the current word to its initial state', (
    tester,
  ) async {
    // 只放一个带释义的单词，便于验证释义步骤也一起回滚。
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

    // 先用提示公开一个字母，制造"非初始状态"。
    await tester.tap(find.byKey(const Key('dictation-hint')));
    await tester.pump();
    _expectTiles(tester, spelling: 'ability', revealedLetterCount: 1);

    // 完整答对拼写与两条释义，进入完成态。
    await tester.tap(find.text('ability'));
    await tester.pump();
    await tester.tap(find.text('能力'));
    await tester.pump();
    await tester.tap(find.text('才能'));
    await tester.pump();
    expect(find.text('当前单词已完成'), findsOneWidget);

    // 点击「再试一次」。
    await tester.tap(find.byKey(const Key('retry-dictation-word')));
    await tester.pump();

    // 回到拼写阶段：提示文案、四个候选、提示与播放按钮全部复位。
    expect(find.text('听音，选出正确的单词'), findsOneWidget);
    expect(find.text('当前单词已完成'), findsNothing);
    _expectFourOptions(tester);
    expect(find.byKey(const Key('dictation-hint')), findsOneWidget);
    expect(find.byKey(const Key('dictation-play')), findsOneWidget);
    // 完成态的两个按钮消失。
    expect(find.byKey(const Key('retry-dictation-word')), findsNothing);
    expect(find.byKey(const Key('next-dictation-word')), findsNothing);
    // 此前公开的字母被收回，字母槽重新全空。
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
        home: DictationPage(
          words: _words,
          audioPlayer: player,
          accent: PronunciationAccent.american,
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
    await tester.tap(find.byKey(const Key('next-dictation-word')));
    await tester.pump();

    // 关键断言：新单词的发音请求必须真的发出去，而不是被"正在播放"挡掉。
    expect(player.requested, <String>['ability', 'ability', 'abandon']);

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
    // 初始七个字母槽全部保留，但没有任何真实字母内容。
    _expectTiles(tester, spelling: 'ability', revealedLetterCount: 0);
    await tester.tap(find.byKey(const Key('dictation-hint')));
    await tester.pump();
    // 第一次提示只填入第一个 a，其余六个槽位保持为空。
    _expectTiles(tester, spelling: 'ability', revealedLetterCount: 1);
    expect(find.text('已显示开头字母'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dictation mirrors listening header and anchors split controls', (
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
          child: DictationPage(
            words: _words,
            audioPlayer: _ImmediateAudioPlayer(),
            accent: PronunciationAccent.american,
          ),
        ),
      ),
    );
    // 等待首帧布局与进入页面后的自动发音状态更新完成。
    await tester.pump();

    // 返回按钮画布与随身听一样，直接从 20 像素页面边距开始。
    final closeRect = tester.getRect(find.byKey(const Key('close-dictation')));
    expect(closeRect.left, DictationLayout.pageInset);
    expect(closeRect.width, DictationLayout.headerButtonSize);
    // 题号的水平中心必须和 390 像素屏幕的中心完全重合。
    final progressLabelRect = tester.getRect(
      find.byKey(const Key('dictation-progress-label')),
    );
    expect(progressLabelRect.center.dx, closeTo(195, 0.01));
    // 进度条左右均保留 20 像素，高度与随身听相同。
    final progressBarRect = tester.getRect(
      find.byKey(const Key('dictation-progress-bar')),
    );
    expect(progressBarRect.left, DictationLayout.pageInset);
    expect(progressBarRect.right, 390 - DictationLayout.pageInset);
    expect(progressBarRect.height, DictationLayout.progressHeight);

    // 按下标从上到下读取四个候选词的真实边界。
    final optionRects = <Rect>[
      for (var index = 0; index < 4; index++)
        tester.getRect(find.byKey(Key('dictation-option-$index'))),
    ];
    // 每个候选词都是独立一行，因此四行必须共用相同左右边界。
    for (final optionRect in optionRects) {
      expect(optionRect.left, closeTo(optionRects.first.left, 0.01));
      expect(optionRect.right, closeTo(optionRects.first.right, 0.01));
      expect(optionRect.height, DictationLayout.optionHeight);
    }
    // 后一行的顶部应等于前一行底部加上统一行间距。
    for (var index = 1; index < optionRects.length; index++) {
      expect(
        optionRects[index].top,
        closeTo(
          optionRects[index - 1].bottom + DictationLayout.optionGap,
          0.01,
        ),
      );
    }
    // 每行左侧都有固定灰色正方形 badge，文字依次为 A、B、C、D。
    for (var index = 0; index < optionRects.length; index += 1) {
      final badgeFinder = find.byKey(Key('dictation-option-badge-$index'));
      final badgeRect = tester.getRect(badgeFinder);
      final labelRect = tester.getRect(
        find.byKey(Key('dictation-option-label-$index')),
      );
      // 方形 badge 的宽高严格相等，并按统一内边距贴齐候选按钮左侧。
      expect(badgeRect.width, DictationLayout.optionBadgeSize);
      expect(badgeRect.height, DictationLayout.optionBadgeSize);
      expect(
        badgeRect.left,
        closeTo(
          // 边框绘制在按钮内容区外侧，实际内容从一像素边框之后开始。
          optionRects[index].left + 1 + DictationLayout.optionHorizontalInset,
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

    // 右侧提示按钮放在播放上方，不再拉到候选区顶部。
    final hintRect = tester.getRect(find.byKey(const Key('dictation-hint')));
    // 提示命令使用灯泡图标，不再只有一段孤立文字。
    expect(
      find.descendant(
        of: find.byKey(const Key('dictation-hint')),
        matching: find.byIcon(TablerIcons.bulb),
      ),
      findsOneWidget,
    );
    // 右侧播放按钮作为最后一项，底边对齐第四个候选词。
    final playRect = tester.getRect(find.byKey(const Key('dictation-play')));
    expect(
      playRect.top,
      closeTo(hintRect.bottom + DictationLayout.optionGap, 0.01),
    );
    expect(playRect.bottom, closeTo(optionRects.last.bottom, 0.01));
    // 提示与播放的整组高度小于四行候选词，因此必须是从底部向上堆叠。
    expect(hintRect.top, greaterThan(optionRects.first.top));
    // 3:1 flex 保证左侧候选词区域占据绝大部分可用宽度。
    expect(optionRects.first.width, closeTo(hintRect.width * 3, 0.01));
    // 操作列底部必须位于系统安全区和页面额外留白之上。
    expect(
      playRect.bottom,
      closeTo(844 - safeBottom - DictationLayout.bottomInset, 0.01),
    );

    // 中部三个子模块必须位于进度条和底部候选区之间，不能与两者重叠。
    final questionContentRect = tester.getRect(
      find.byKey(const Key('dictation-question-content')),
    );
    expect(
      questionContentRect.top,
      closeTo(
        progressBarRect.bottom + DictationLayout.questionVerticalInset,
        0.01,
      ),
    );
    expect(questionContentRect.bottom, lessThan(optionRects.first.top));
    // 三个同级模块按“单词卡、独立提示横幅、全量步骤”居上排列。
    final wordCardRect = tester.getRect(
      find.byKey(const Key('dictation-word-card')),
    );
    final promptInformationRect = tester.getRect(
      find.byKey(const Key('dictation-prompt-information')),
    );
    final stepsSectionRect = tester.getRect(
      find.byKey(const Key('dictation-vertical-steps')),
    );
    final stageRect = tester.getRect(
      find.byKey(const Key('dictation-stage-label')),
    );
    final feedbackRect = tester.getRect(
      find.byKey(const Key('dictation-feedback-slot')),
    );
    expect(wordCardRect.top, questionContentRect.top);
    expect(promptInformationRect.top, greaterThan(wordCardRect.bottom));
    expect(stepsSectionRect.top, greaterThan(promptInformationRect.bottom));
    // 提示到全部步骤使用同一条 Tabler Steps vertical 轨道。
    expect(find.byKey(const Key('dictation-vertical-steps')), findsOneWidget);
    final promptMarkerRect = tester.getRect(
      find.byKey(const Key('dictation-step-marker-0')),
    );
    final meaningMarkerRect = tester.getRect(
      find.byKey(const Key('dictation-step-marker-1')),
    );
    final connectorRect = tester.getRect(
      find.byKey(const Key('dictation-step-connector-0')),
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
}

/// 断言当前小题始终存在精确四个候选项。
void _expectFourOptions(WidgetTester tester) {
  // 下标 0..3 都必须各有一个选项。
  for (var index = 0; index < 4; index++) {
    expect(find.byKey(Key('dictation-option-$index')), findsOneWidget);
  }
  // 下标 4 不允许出现，以此排除意外生成第五项。
  expect(find.byKey(const Key('dictation-option-4')), findsNothing);
}

/// 断言当前单词完成后四个候选项已经全部卸载。
void _expectNoOptions(WidgetTester tester) {
  // 逐个检查原四个固定下标。
  for (var index = 0; index < 4; index++) {
    expect(find.byKey(Key('dictation-option-$index')), findsNothing);
  }
}

/// 断言一个英文字母严格对应一个固定瓷砖，并核对当前公开的字母数量。
void _expectTiles(
  WidgetTester tester, {
  required String spelling,
  required int revealedLetterCount,
}) {
  // 本测试数据都是普通英文单词，因此字符串下标与页面英文字母下标一致。
  for (var index = 0; index < spelling.length; index += 1) {
    // 每个字母必须存在独立字母瓷砖，不能退回一整串下划线文本。
    expect(find.byKey(Key('dictation-tile-$index')), findsOneWidget);
    // 直接读取瓷砖内 Text 的值，避免页面其他候选词文本干扰断言。
    final letterText = tester.widget<Text>(
      find.byKey(Key('dictation-tile-letter-$index')),
    );
    // 字母字号跟随布局常量，不能被后续局部样式意外覆盖。
    expect(letterText.style?.fontSize, DictationLayout.wordLetterFontSize);
    // 提示范围以内显示大写真实字母，其余瓷砖保持空字符串。
    expect(
      letterText.data,
      index < revealedLetterCount ? spelling[index].toUpperCase() : '',
    );
  }
  // 单词长度之外不允许多出额外字母瓷砖。
  expect(
    find.byKey(Key('dictation-tile-${spelling.length}')),
    findsNothing,
  );
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

/// 模拟真实原生播放器：play 的 Future 会一直挂起直到音频播完，
/// 新的 play 会把上一个请求以「已被替换」的中断异常结束（与 Android 实现一致）。
class _PendingAudioPlayer implements WordAudioPlayer {
  /// 依次记录每一次被请求播放的单词，供测试断言播放顺序。
  final List<String> requested = <String>[];

  /// 当前尚未结束的那次播放；Completer 相当于一个"手动兑现的 Promise"。
  Completer<void>? _pending;

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

  @override
  Future<void> stop() async {
    // 停止同样让挂起的播放以中断异常收尾。
    _completePending();
  }

  /// 结束当前挂起的播放；页面会把这个异常当作"被替换"而静默忽略。
  void _completePending() {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const WordAudioInterruptedException());
    }
  }
}
