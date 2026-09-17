import '../../../widgets/question_content_transition.dart';
import '../../../widgets/audio_playback_capsule.dart';

import 'package:flutter/material.dart';

import '../../../common/theme.dart';
import '../../../widgets/audio_speaker_button.dart';
import '../../../widgets/answer_slots.dart';
import '../../../widgets/pos_meaning_panel.dart';
import 'listening_meaning_layout.dart';

///
/// 听音辨义单词的某一学习步骤。
///
/// 页面仍然按“先选单词、再选释义”的业务顺序生成步骤；正文只读取这些状态，
/// 并把它们排成 `ui/听音辨义1.html` 中的“单词 + 释义槽位”版式。
///
class ListeningMeaningStep {
  /// 创建一条步骤；业务状态仍由父页面管理。
  const ListeningMeaningStep({
    required this.kind,
    required this.title,
    required this.status,
    this.pos,
    this.definitions,
    this.definitionTexts,
    this.word,
  });

  /// 步骤类型：听音选词，或选择中文释义。
  final ListeningMeaningStepKind kind;

  /// 步骤主标题，显示在白色正文卡片顶部。
  final String title;

  /// 步骤当前状态。
  final ListeningMeaningStepStatus status;

  /// 释义步骤的词性，例如 `n.` / `vt.`。
  final String? pos;

  /// 这一词性下的全部释义，仅用于让未揭示的占位符按真实含义计算宽度。
  ///
  /// 占位符仍然不会显示这些文字；它们只像量尺一样提供对应的长度，避免
  /// 所有未答释义都退化成同一个固定宽度，或错误地撑满整行。
  final List<String>? definitionTexts;

  /// 这一词性下已经答对、可以公开的释义。
  final List<String>? definitions;

  /// 听音步骤完成后展示的正确单词。
  final String? word;
}

/// 听音辨义的两个答题阶段。
enum ListeningMeaningStepKind {
  /// 根据发音选择正确英文拼写。
  word,

  /// 选择当前词性的中文释义。
  meaning,
}

/// 步骤的三种展示状态。
enum ListeningMeaningStepStatus {
  /// 已经答对。
  done,

  /// 正在作答。
  active,

  /// 尚未开始。
  pending,
}

///
/// 听音辨义页面的正文区域。
///
/// 版式对齐 `ui/听音辨义1.html`：
///
/// - 听音阶段显示圆形播放入口、标题、副标题和字母遮罩；
/// - 释义阶段显示大号单词、释义槽位和底部操作提示；
/// - 原型中“音标 + 小播音按钮”的位置替换成拼写巩固同款播音胶囊。
///
/// 候选答案仍由页面底部负责，本组件只负责正文展示，不改变答题和记录逻辑。
///
class ListeningMeaningQuestionContent extends StatelessWidget {
  /// 创建听音辨义正文。
  const ListeningMeaningQuestionContent({
    required this.spelling,
    required this.revealWholeWord,
    required this.onSpeakerTap,
    required this.isPlaying,
    required this.steps,
    required this.definitionSeparator,
    required this.accentLabel,
    this.wordRevealToken,
    this.onWordRevealSettled,
    // 底部结果提示三件套由页面算好传进来，不传即不展示提示。
    this.hintText,
    this.hintColor,
    this.hintIcon,
    super.key,
  });

  /// 当前单词的完整拼写；听音阶段只用于计算遮罩线数量。
  final String spelling;

  /// 释义阶段或完成态时显示完整单词。
  final bool revealWholeWord;

  /// 点击正文中的播放入口时执行父页面的真实发音逻辑。
  final VoidCallback onSpeakerTap;

  /// 当前单词是否正在播放。
  final bool isPlaying;

  /// 当前单词的完整步骤状态。
  final List<ListeningMeaningStep> steps;

  /// 多条释义的无障碍朗读分隔符。
  final String definitionSeparator;

  /// 当前口音的中文名称，显示在播音胶囊第二行。
  final String accentLabel;

  /// 听音阶段选对单词后的「入场票」：不为 null 时字母格整词填入并转绿。
  ///
  /// 页面选对的那一刻发一张票，字母依次弹出；动画播完后经
  /// [onWordRevealSettled] 通知页面，页面再切到释义阶段。这样选对与切换
  /// 之间的那几百毫秒里屏幕上是有内容的，而不是干等。
  final int? wordRevealToken;

  /// 听音阶段整词填入的动画播完时调用。
  final VoidCallback? onWordRevealSettled;

  /// 卡片底部的结果提示文案（错误次数 / 全对），为 null 表示当前不展示提示。
  ///
  /// 提示原本悬浮在白卡与候选区之间，现在改为贴到白卡内部底部，因此这个值
  /// 由页面按「是否出错 / 是否全对」算好后传进来。
  final String? hintText;

  /// 提示的语义色（危险红 / 成功绿），与 [hintText] 同时为 null 时不渲染。
  final Color? hintColor;

  /// 提示前的 Tabler 图标，与 [hintText] 同时为 null 时不渲染。
  final IconData? hintIcon;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // 正文白卡不再绘制顶部状态条 / 步骤条：题目进度已由页面顶栏的总进度条统一
    // 承载，白卡内只保留「听音 / 释义」正文与底部的结果提示，信息更聚焦。

    return Container(
      key: const Key('listening-meaning-question-card'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: tokens.card,
        // 与候选词、描边按钮、输入框同一档控件描边；白卡只靠这一圈线立在灰底上，
        // 不再叠投影。
        border: Border.all(color: tokens.rowBorder, width: AppStroke.thin),
        // 正文白卡的圆角走本页尺寸表：拼写巩固与看义选词的注释都写着「与听音辨义
        // 题目卡一致」，现在这句话真的指着同一个常量了。
        borderRadius: BorderRadius.circular(
          ListeningMeaningLayout.bodyCardRadius,
        ),
      ),
      // IntrinsicHeight 会把父级提供的最小卡片高度传给内容列；
      // 内容较少时正文区吃掉剩余空间，内容较多时仍会自然增高并允许外层滚动。
      child: IntrinsicHeight(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                key: const Key('listening-meaning-card-body'),
                // 正文内容到白卡四边的距离统一为 pBase：以前这里四边都是 0，
                // 词性及含义会直接贴到卡片边缘，看起来不像“装在卡片里”。
                // 四边同值，用 `EdgeInsets.all` 简写。
                padding: const EdgeInsets.all(AppSpace.pBase),
                child: Center(
                  child: QuestionContentTransition(
                    contentKey: (spelling, revealWholeWord),
                    child: revealWholeWord
                        ? _MeaningStage(
                            spelling: spelling,
                            isPlaying: isPlaying,
                            onSpeakerTap: onSpeakerTap,
                            steps: steps,
                            definitionSeparator: definitionSeparator,
                            accentLabel: accentLabel,
                            tokens: tokens,
                          )
                        : _ListenStage(
                            spelling: spelling,
                            isPlaying: isPlaying,
                            onSpeakerTap: onSpeakerTap,
                            revealToken: wordRevealToken,
                            onRevealSettled: onWordRevealSettled,
                            tokens: tokens,
                          ),
                  ),
                ),
              ),
            ),
            // 结果提示（错误次数 / 全对）贴在白卡底部：比原本悬浮在白卡与候选区
            // 之间更紧凑，也避免正文与候选区之间再额外留一道间距。
            if (hintText != null && hintColor != null && hintIcon != null)
              _CardBottomHint(
                key: const Key('listening-meaning-difficulty-hint'),
                text: hintText!,
                color: hintColor!,
                icon: hintIcon!,
              ),
          ],
        ),
      ),
    );
  }
}

///
/// 正文白卡底部的结果提示（错误次数 / 全对）。
///
/// 就是一行「图标 + 文案」，语义全靠图标与文字颜色表达（危险红 / 成功绿）：
/// 它已经身在白卡内部，白卡本身就是一张卡片，所以不再额外包圆角胶囊，
/// 免得变成“卡中卡”。
class _CardBottomHint extends StatelessWidget {
  const _CardBottomHint({
    required this.text,
    required this.color,
    required this.icon,
    super.key,
  });

  /// 提示文案，例如「本题已答错 2 次」「一气呵成 · 完美通过！」。
  final String text;

  /// 语义色：危险红（出错）或成功绿（全对）。
  final Color color;

  /// 提示前的 Tabler 图标（告警 / 全对）。
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      // 四边同为 p3 时用 `EdgeInsets.all` 这一档简写（相当于 CSS 的 padding: p3），
      // 比 fromLTRB 写四个一样的数更短，也不会出现“改了三边漏一边”。
      padding: const EdgeInsets.all(AppSpace.p3),
      // Center 让这行「图标 + 文案」在白卡内水平居中。
      child: Center(
        // 刻意不再包一层圆角胶囊：提示就在白卡内部，白卡本身已经是卡片，
        // 再叠一层带底色和描边的胶囊等于“卡中卡”，反而显得啰嗦。
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppIcon.i16, color: color),
            const SizedBox(width: AppSpace.p2),
            Text(text, style: textTheme.fs5Semibold.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

/// 听音阶段：对应原型中“圆形播音按钮 + 这个单词是？”正文。
class _ListenStage extends StatelessWidget {
  const _ListenStage({
    required this.spelling,
    required this.isPlaying,
    required this.onSpeakerTap,
    required this.revealToken,
    required this.onRevealSettled,
    required this.tokens,
  });

  final String spelling;
  final bool isPlaying;
  final VoidCallback onSpeakerTap;

  /// 选对后的入场票；为 null 表示还在作答，字母格全是空位。
  final int? revealToken;

  /// 整词填入动画播完时的通知。
  final VoidCallback? onRevealSettled;

  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final revealed = revealToken != null;

    return Column(
      key: const Key('listening-meaning-question-content'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 这个大圆对应 HTML 原型的 `.speaker`，直径记在页面表里，仍使用 Tabler 扬声器。
        AudioSpeakerButton(
          key: const Key('listening-meaning-word-card-speaker'),
          isPlaying: isPlaying,
          onTap: onSpeakerTap,
          size: ListeningMeaningLayout.questionSpeakerSize,
          iconSize: AppIcon.i32,
        ),
        const SizedBox(height: AppSpace.pBase),
        Text(
          '这个单词是？',
          key: const Key('listening-meaning-stage-title'),
          style: textTheme.fs3Semibold,
        ),
        const SizedBox(height: AppSpace.p2),
        Text(
          '仔细听发音，在下方选出正确的单词',
          key: const Key('listening-meaning-stage-subtitle'),
          style: textTheme.fs5.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpace.pBase),
        // 答案槽位：与拼写巩固 / 看义选词共用同一个 AnswerSlots，三个模块的
        // 「填空」观感完全一致。作答中字母格全部是空位，光标自动落在第一个
        // 字母上；选对后整词填入、字母依次弹出并转绿。撇号、连字符、空格这类
        // 静态字符从一开始就显示（`o'clock` 的撇号以前在这里被过滤掉了）。
        AnswerSlots(
          key: const Key('listening-meaning-spelling-mask'),
          tone: revealed ? AnswerSlotTone.correct : AnswerSlotTone.neutral,
          showCaret: !revealed,
          onSettled: onRevealSettled,
          cells: [
            for (var index = 0; index < spelling.length; index += 1)
              AnswerSlots.isLetter(spelling[index])
                  ? AnswerSlotCell(
                      text: spelling[index],
                      filled: revealed,
                      entryToken: revealToken,
                      key: Key('listening-meaning-mask-$index'),
                    )
                  : AnswerSlotCell.static(
                      spelling[index],
                      key: Key('listening-meaning-mask-$index'),
                    ),
          ],
        ),
      ],
    );
  }
}

/// 释义阶段：对应原型中“大号单词 + 播音区域 + 释义槽位”。
class _MeaningStage extends StatelessWidget {
  const _MeaningStage({
    required this.spelling,
    required this.isPlaying,
    required this.onSpeakerTap,
    required this.steps,
    required this.definitionSeparator,
    required this.accentLabel,
    required this.tokens,
  });

  final String spelling;
  final bool isPlaying;
  final VoidCallback onSpeakerTap;
  final List<ListeningMeaningStep> steps;
  final String definitionSeparator;
  final String accentLabel;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final meaningSteps = steps
        .where((step) => step.kind == ListeningMeaningStepKind.meaning)
        .toList(growable: false);
    // 顶部 steps 按“每条释义一次选择”展示；正文则把相邻的相同词性重新合并，
    // 这样 hard 的 6 个步骤会完整出现在进度条中，但正文仍只显示一个“*”标签，
    // 右侧排列这组词性的 6 个含义槽位。
    final rows = <_MeaningRowBuilder>[];
    // 已答对的条数与当前正在作答的下标，都按“摊平后的第几条释义”计。
    // 这个口径与页面里的 _meaningIndex 完全一致，公共面板直接按它决定
    // 哪几条已经公开、哪一条要显示闪烁光标。
    var revealedCount = 0;
    int? activeIndex;
    for (var index = 0; index < meaningSteps.length; index += 1) {
      final step = meaningSteps[index];
      final pos = step.pos ?? '*';
      if (rows.isEmpty || rows.last.pos != pos) {
        rows.add(_MeaningRowBuilder(pos: pos));
      }
      // 未答释义也要把真实文字交给面板：它要垫在底层当尺子，撑出与答对后
      // 完全相同的宽度，这样答对时页面一个像素都不会动。
      rows.last.definitions.add(
        step.definitionTexts?.isNotEmpty == true
            ? step.definitionTexts!.first
            : (step.definitions?.isNotEmpty == true
                  ? step.definitions!.first
                  : ''),
      );
      if (step.status == ListeningMeaningStepStatus.done) revealedCount += 1;
      if (step.status == ListeningMeaningStepStatus.active) activeIndex = index;
    }

    return Column(
      key: const Key('listening-meaning-question-content'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          spelling,
          key: const Key('listening-meaning-word'),
          textAlign: TextAlign.center,
          // 全站最大号那一档；这里的单词是本页视觉焦点，行距收紧一点，
          // 让长单词不至于把这一行撑得太高。
          style: textTheme.display6.copyWith(
            height: ListeningMeaningLayout.wordLineHeight,
          ),
        ),
        // 这里刻意不显示音标和独立小喇叭，直接替换为拼写巩固的播音胶囊。
        // 上方间距与下方分割线的 26px 上边距保持一致，让播音胶囊在单词与释义
        // 之间处于均衡的位置，不会视觉上贴近其中一侧。
        const SizedBox(height: AppSpace.pBase),
        AudioPlaybackCapsule(
          key: const Key('listening-meaning-playback-status'),
          isPlaying: isPlaying,
          onTap: onSpeakerTap,
          accentLabel: accentLabel,
        ),
        // 释义区整块交给公共面板，与“拼写巩固”共用同一套版式：
        // 那边是只读模式，这边是揭示模式——答对一条就原地揭开一条。
        //
        // 注意：以前这里包了一层 maxWidth 300 的限宽，面板被卡成窄条，又被
        // 外层 Center 水平居中，于是面板到白卡左右边缘各空出几十像素
        // （远超 pBase），怎么调卡片内边距都看不见变化——对称内边距包着
        // 一块被居中、又比可用区窄的内容，距离天然不变。去掉限宽让面板
        // 横向铺满卡片内容区后，卡边到面板边正好是正文的 pBase 内边距。
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpace.pBase),
            PosMeaningPanel.reveal(
              rows: [
                for (final row in rows)
                  PosMeaningRow(pos: row.pos, definitions: row.definitions),
              ],
              separator: definitionSeparator,
              revealedCount: revealedCount,
              activeIndex: activeIndex,
              keyPrefix: 'listening-meaning',
            ),
          ],
        ),
      ],
    );
  }
}

/// 正文中的一个词性行，只在组装面板数据的过程里临时用一下。
///
/// 顶部进度条使用逐条释义的 step；这里仅为视觉排版服务，把同一词性下的
/// 多个 step 收拢到同一行中。
class _MeaningRowBuilder {
  _MeaningRowBuilder({required this.pos});

  final String pos;
  final List<String> definitions = <String>[];
}

///
/// 听音辨义正文复用拼写巩固的播音胶囊视觉。
///
/// 播放状态只驱动一组低频声纹，不依赖页面的业务定时器；这样正文滚动、切题
/// 和系统返回时，胶囊都能自行停止动画，不会把状态更新泄漏到已离场页面。
