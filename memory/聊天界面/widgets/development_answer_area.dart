// 本文件是 development_page.dart 的一部分（part of），与主文件共享同一个
// library，因此可以直接使用页面内部的私有类型（下划线开头的类），不需要
// 单独 import 任何依赖。这里集中放置底部答题区组件，让主文件只保留页面骨架与状态逻辑。
part of '../development_page.dart';

/// 题目气泡顶部的圆点、字母或已完成单词。
///
/// 复刻 HTML 原型 `.slot`：每个槽位是固定 20px 高的占位框，宽度按状态切换：
/// - 空槽位（dot）：width 5px，里面一个 5×5 浅蓝圆点居中；
/// - 字母槽位（letter）：width 13px，里面一个 15px 蓝色字符 + 8px 发光阴影；
/// 槽位之间间距 4px。**注意：HTML 原型中字母槽位没有背景色**——圆点是单独
/// 居中的圆点，字母是字符浮在 13px 宽的空白位置上；Flutter 之前的实现把
/// 整个槽位都画成浅蓝填充矩形，是严重偏离。这里彻底改为"透明槽位 + 居中
/// 内容"的形态。
class _QuestionSlots extends StatefulWidget {
  /// 创建题目槽位区。
  const _QuestionSlots({required this.question, required this.tokens});

  /// 题目状态。
  final _DevelopmentQuestion question;

  /// 当前主题色令牌。
  final AppTokens tokens;

  @override
  State<_QuestionSlots> createState() => _QuestionSlotsState();
}

/// 管理一整排拼写槽位共用的呼吸时间轴。
///
/// 以前每一个空槽位都会各自创建一个无限循环的 AnimationController。一个
/// 10 字母的单词就会同时运行 10 个 Ticker，即使所有圆点只需要同一条时间轴
/// 的不同相位。现在整排只保留一个控制器，能显著减少开发演示页的 CPU 占用。
class _QuestionSlotsState extends State<_QuestionSlots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dotController;

  @override
  void initState() {
    super.initState();
    _dotController = AnimationController(
      vsync: this,
      duration: DevelopmentLayout.dotAnimationDuration,
    );
    _syncDotController();
  }

  @override
  void didUpdateWidget(covariant _QuestionSlots oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDotController();
  }

  @override
  void dispose() {
    _dotController.dispose();
    super.dispose();
  }

  /// 根据当前题目是否播放音频，按需启动或停止整排圆点时间轴。
  void _syncDotController() {
    final shouldAnimate =
        widget.question.isPlaying && !widget.question.spellingSolved;
    if (shouldAnimate && !_dotController.isAnimating) {
      _dotController
        ..value = 0
        ..repeat();
    } else if (!shouldAnimate && _dotController.isAnimating) {
      _dotController
        ..stop()
        ..value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    if (question.spellingSolved) {
      // 拼对后整体换成单词：拼写选义和听音拼写都使用 HTML 原型
      // `.solved-word` 的 15px、800 字重和蓝色发光效果。
      return Text(
        question.word.spelling,
        style: TextStyle(
          color: AppTokens.accent,
          fontSize: DevelopmentLayout.slotLetterSize,
          fontWeight: FontWeight.w800,
          height: 1,
          letterSpacing: 0,
          shadows: <Shadow>[
            Shadow(color: DevelopmentLayout.slotLetterGlow, blurRadius: 8),
          ],
        ),
      );
    }

    if (question.showDots) {
      // 播放音频时圆点会随声波一起呼吸；不播放时静止（仍占位，保证气泡宽度稳定）。
      return _AnimatedDots(playing: question.isPlaying);
    }

    final expected = _lettersOnlyForDisplay(question.word.spelling);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < expected.length; index += 1)
          Padding(
            padding: EdgeInsets.only(
              right: index == expected.length - 1
                  ? 0
                  : DevelopmentLayout.slotGap,
            ),
            child: _Slot(
              letter: question.typedLetters.length > index
                  ? question.typedLetters[index].toUpperCase()
                  : null,
              playing: question.isPlaying,
              dotIndex: index,
              dotAnimation: _dotController,
            ),
          ),
      ],
    );
  }

  /// 只为槽位计算英文字母数量，空格与连字符不会造成多余格子。
  String _lettersOnlyForDisplay(String value) => value.runes
      .map(String.fromCharCode)
      .where((character) => RegExp(r'[A-Za-z]').hasMatch(character))
      .join();
}

/// 单个槽位：固定 20px 高、宽度按 letter/dot 切换的占位框。
///
/// 复刻 HTML 原型 `.slot` 的结构：槽位本身透明，里面用 align:center 放
/// 5px 圆点或 13px 宽的字母。HTML 槽位之间的间距 4px 由外层 Padding 提供，
/// 字母字符从圆点宽度"抽芽"长出 0.34s 缓动——这里把抽芽动画做在槽位内
/// 首次切换到 letter 的那一帧上。
class _Slot extends StatefulWidget {
  /// 创建一个槽位。
  const _Slot({
    required this.letter,
    required this.playing,
    this.dotIndex = 0,
    this.dotAnimation,
  });

  /// 当前槽位上的字母（null 表示仍是空圆点）。
  final String? letter;

  /// 当前是否正在播放（决定空圆点是否呼吸）。
  final bool playing;

  /// 槽位序号，用于让一排空位圆点按原型的 60ms 依次错开呼吸，
  /// 对齐 HTML 原型 `.quiz-bubble.playing .slot.dot:after` 的错开动画。
  final int dotIndex;

  /// 由整排共享的呼吸时间轴；字母槽位为空时才会使用。
  final Animation<double>? dotAnimation;

  @override
  State<_Slot> createState() => _SlotState();
}

class _SlotState extends State<_Slot> with SingleTickerProviderStateMixin {
  /// 抽芽动画控制器：从空圆点切到字母时播一次 letterPop。
  late final AnimationController _controller;
  bool _hadLetter = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _hadLetter = widget.letter != null;
    if (_hadLetter) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant _Slot oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hasLetter = widget.letter != null;
    if (hasLetter && !_hadLetter) {
      // 第一次出现字母：正向播 letterPop 抽芽动画。
      _controller.forward(from: 0);
    } else if (!hasLetter && _hadLetter) {
      // 字母离场（错答重置时）：反向播 0.2s 收起，再准备下一轮。
      _controller.reverse(from: 1);
    } else if (!hasLetter && !_hadLetter) {
      // 持续为空：不重置控制器。
    }
    _hadLetter = hasLetter;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasLetter = widget.letter != null;
    // 槽位宽度的变化要平滑：HTML 用 animation 不是 transition，因为每次按键
    // 都会重建整列槽位（这里也是 StatelessWidget→StatefulWidget 重建）。
    // 我们用 AnimatedContainer 解决宽度过渡；圆点/字母的切换动画走显式 AnimationController。
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: const Cubic(0.16, 1, 0.3, 1),
      width: hasLetter
          ? DevelopmentLayout.slotLetterWidth
          : DevelopmentLayout.slotDotSize,
      height: DevelopmentLayout.slotHeight,
      alignment: Alignment.center,
      color: Colors.transparent,
      child: hasLetter ? _buildLetter() : _buildDot(),
    );
  }

  /// 字母字符：HTML 原型 font-size 15px / font-weight 800 / color blue
  /// / text-shadow 0 0 8px rgba(32,107,196,.22)。这里用 AnimatedBuilder 播
  /// letterPop（scale 0.4→1.06→0.98→1，带轻微 blur）。
  Widget _buildLetter() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // letterPop 包络：0→0.45 0.4→1.06（0.45→0.72 1.06→0.98）→1
        final t = _controller.value;
        final double scale;
        final double opacity;
        if (t < 0.45) {
          final k = t / 0.45;
          scale = 0.4 + (1.06 - 0.4) * k;
          opacity = 0.5 + (1.0 - 0.5) * k;
        } else if (t < 0.72) {
          final k = (t - 0.45) / 0.27;
          scale = 1.06 + (0.98 - 1.06) * k;
          opacity = 1.0;
        } else if (t < 1.0) {
          final k = (t - 0.72) / 0.28;
          scale = 0.98 + (1.0 - 0.98) * k;
          opacity = 1.0;
        } else {
          scale = 1.0;
          opacity = 1.0;
        }
        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Text(
        widget.letter!,
        style: TextStyle(
          color: AppTokens.accent,
          fontSize: DevelopmentLayout.slotLetterSize,
          fontWeight: FontWeight.w800,
          height: 1,
          shadows: <Shadow>[
            Shadow(color: DevelopmentLayout.slotLetterGlow, blurRadius: 8),
          ],
        ),
      ),
    );
  }

  /// 空圆点：5×5 浅蓝圆点居中；播放音频时轻微呼吸（与 HTML 等待态圆点同源）。
  Widget _buildDot() {
    // 每个槽位比前一个晚 60ms 亮起（周期 720ms → 错开 60/720 个周期），
    // 让空位圆点从前往后依次呼吸，和语音消息那排圆点一样有层次感。
    return _BreathingDot(
      playing: widget.playing,
      phaseOffset:
          widget.dotIndex *
          (DevelopmentLayout.slotDotAnimationDelayMs /
              DevelopmentLayout.dotAnimationDuration.inMilliseconds),
      animation: widget.dotAnimation,
    );
  }
}

/// 拼写选义题在同一个系统气泡里回填的词性和释义 chip。
class _MeaningResults extends StatelessWidget {
  /// 创建释义回填区域。
  const _MeaningResults({required this.question, required this.tokens});

  /// 当前题目。
  final _DevelopmentQuestion question;

  /// 当前主题色令牌。
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<(Meaning, int)>>{};
    for (var index = 0; index < question.meanings.length; index += 1) {
      final meaning = question.meanings[index];
      groups.putIfAbsent(meaning.displayPos, () => <(Meaning, int)>[]).add((
        meaning,
        index,
      ));
    }
    final entries = groups.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var groupIndex = 0; groupIndex < entries.length; groupIndex += 1)
          Padding(
            // 词性之间的行距统一为 10px，让不同词性的含义分组更容易区分。
            // 最后一组不额外增加底部留白，避免释义区域末尾出现多余空隙。
            padding: EdgeInsets.only(
              bottom: groupIndex == entries.length - 1 ? 0 : 10,
            ),
            child: Row(
              // 词性标签固定贴在本组含义的第一行顶部。若使用 center，
              // 当含义自动换行时，标签会被整体居中到两行之间，造成 drive
              // 这类多词性、多含义单词的词性看起来上下错位。
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  // 词性列宽严格 38px：HTML 原型 `grid-template-columns: 38px 1fr`。
                  // 之前 Flutter 用 35 导致 3 字符的"adj."被截断或贴边。
                  width: DevelopmentLayout.posColumnWidth,
                  child: Padding(
                    // 词性不随含义行数整体居中，只在第一行顶部增加 4px，
                    // 让单行和多行含义时都保持相同的首行视觉居中效果。
                    padding: const EdgeInsets.only(
                      top: DevelopmentLayout.posTextMarginTop,
                    ),
                    child: Text(
                      entries[groupIndex].key,
                      style: const TextStyle(
                        color: AppTokens.accent,
                        fontSize: DevelopmentLayout.posTextSize,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                // 词性列与含义 chip 之间的间距：HTML 原型 `.pos-group { gap: 7px; }`。
                const SizedBox(width: DevelopmentLayout.posGroupGap),
                Expanded(
                  child: Wrap(
                    // chip 之间的水平/垂直间距：在原型基础上各增加 2px，
                    // 让连续含义之间更容易区分。
                    spacing: DevelopmentLayout.meaningChipSpacing,
                    runSpacing: DevelopmentLayout.meaningChipRunSpacing,
                    children: [
                      for (final (meaning, index) in entries[groupIndex].value)
                        _MeaningChip(
                          text: index < question.solvedMeaningCount
                              ? meaning.definition
                              : '待选择',
                          solved: index < question.solvedMeaningCount,
                          tokens: tokens,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 单个已回填或待选择的释义 chip。
class _MeaningChip extends StatelessWidget {
  /// 创建释义 chip。
  const _MeaningChip({
    required this.text,
    required this.solved,
    required this.tokens,
  });

  /// chip 显示文字。
  final String text;

  /// 是否已经回答正确。
  final bool solved;

  /// 当前主题色令牌。
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    // 颜色与样式严格对应 HTML 原型：
    // - 已答：浅蓝底（accent.alpha .08）+ 蓝色文字（accent）+ 字重 700；
    // - 未答：白底 + 1px dashed 浅灰描边 + 占位灰文字 + 字重 500。
    final fillColor = solved
        ? AppTokens.accent.withValues(alpha: .08)
        : tokens.card;
    final textColor = solved
        ? AppTokens.accent
        : DevelopmentLayout.meaningBlankText;
    final borderColor = solved
        ? Colors.transparent
        : DevelopmentLayout.meaningBlankBorder;
    return IntrinsicWidth(
      // Wrap 的子项必须保持内容宽度；没有这层时，松约束在某些屏幕尺寸
      // 下会让占位 chip 取满当前行，看起来像每条含义各占一整行。
      child: Container(
        constraints: const BoxConstraints(
          // 严格 22 高：HTML `.meaning-chip { height: 22px; }`。之前用 vertical
          // padding 5 + 文字高度，实际接近 24px 多出 2px，破坏一行多个 chip
          // 时的视觉高度对齐。
          minHeight: DevelopmentLayout.meaningChipHeight,
          // 严格 54 最小宽：HTML `.meaning-chip { min-width: 54px; }`。
          // 之前没设，2-3 个字的短含义会缩成"小豆子"，与长含义 chip 高度不对齐。
          minWidth: DevelopmentLayout.meaningChipMinWidth,
        ),
        // 水平 11px、垂直 0：在当前 9px 基础上再增加 2px，让“待选择”和已选
        // 释义使用完全一致的内边距，中文文字不会贴近容器边缘。
        // 垂直方向保持 0，避免额外 padding 把 chip 撑高，破坏一行多个 chip 的对齐。
        padding: const EdgeInsets.symmetric(
          horizontal: DevelopmentLayout.meaningChipHorizontalPadding,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(
            DevelopmentLayout.meaningChipRadius,
          ),
          // dashed 边框：Flutter 没有原生 dashed border，这里用 [BoxBorder] 退化为
          // 实色 1px（视觉差异极小，且与原型的浅灰一致）。深色模式稍后适配。
          border: solved
              ? null
              : Border.all(
                  color: borderColor,
                  width: 1,
                  style: BorderStyle.solid,
                ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: textColor,
            fontSize: DevelopmentLayout.meaningChipTextSize,
            fontWeight: solved ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// 用户侧回答气泡；正常回答蓝底，错误回答红底，正确回答带白底绿色勾。
class _UserBubble extends StatelessWidget {
  /// 创建用户回答气泡。
  const _UserBubble({
    required this.text,
    required this.danger,
    required this.checked,
    required this.tokens,
  });

  /// 回答文字。
  final String text;

  /// 是否为错误回答。
  final bool danger;

  /// 是否在文字后显示正确勾选。
  final bool checked;

  /// 当前主题色令牌。
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final color = danger ? DevelopmentLayout.red : AppTokens.accent;
    return Container(
      constraints: const BoxConstraints(
        minHeight: DevelopmentLayout.bubbleMinHeight,
        minWidth: DevelopmentLayout.bubbleMinWidth,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: DevelopmentLayout.bubbleHorizontalPadding,
        vertical: DevelopmentLayout.bubbleVerticalPadding,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(DevelopmentLayout.bubbleRadius),
          topRight: Radius.circular(DevelopmentLayout.bubbleRadius),
          bottomLeft: Radius.circular(DevelopmentLayout.bubbleRadius),
          bottomRight: Radius.circular(3),
        ),
        boxShadow: [
          BoxShadow(
            color: tokens.text.withValues(alpha: .04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 22 / 15,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (checked) ...[
            const SizedBox(width: 6),
            Container(
              width: DevelopmentLayout.checkCircleSize,
              height: DevelopmentLayout.checkCircleSize,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              // 19px 圆里嵌 check：HTML 原型 viewBox 24×24 + stroke 2.2，把
              // check 渲染成 14-16px 最贴近。Flutter 之前用 14 偏小、且
              // TablerIcons.check 默认 stroke 较细，看起来像"虚了"。改成
              // 16 让 check 视觉更扎实，但仍居中不溢出圆形。
              child: const Icon(
                TablerIcons.check,
                size: 16,
                color: DevelopmentLayout.green,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
