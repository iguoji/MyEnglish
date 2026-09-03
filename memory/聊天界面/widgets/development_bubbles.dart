// 本文件是 development_page.dart 的一部分（part of），与主文件共享同一个
// library，因此可以直接使用页面内部的私有类型（下划线开头的类），不需要
// 单独 import 任何依赖。这里集中放置聊天气泡类组件，让主文件只保留页面骨架与状态逻辑。
part of '../development_page.dart';

///
/// 原型里的“正在输入”气泡。
///
/// 三个圆点直接复用语音消息的 `.voice-dots` 动画，只把数量改成 3；
/// 这样加载态和语音态的节奏、放大幅度、颜色过渡完全一致。
class _TypingBubble extends StatelessWidget {
  /// 创建等待气泡。
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return _SystemBubbleContainer(
      tokens: tokens,
      child: const _AnimatedDots(playing: true, count: 3),
    );
  }
}

///
/// 系统侧普通文字气泡，用于看义选词题的中文提示。
///
class _SystemTextBubble extends StatelessWidget {
  /// 创建系统文字气泡。
  const _SystemTextBubble({required this.text, required this.tokens});

  /// 要显示的中文含义。
  final String text;

  /// 当前主题色令牌。
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return _SystemBubbleContainer(
      tokens: tokens,
      child: Text(
        text,
        style: TextStyle(color: tokens.text, fontSize: 15, height: 22 / 15),
      ),
    );
  }
}

///
/// 系统侧题目气泡：左边 Tabler 音量图标，右边圆点或拼写内容。
///
/// 拼写选义题拼对后会在同一气泡下方回填释义列表，气泡随内容撑满聊天宽度，
/// 对应 HTML 原型 `.quiz-bubble:has(.meaning-results) { width: 100%; }`。
///
class _QuestionBubble extends StatelessWidget {
  /// 创建题目气泡。
  const _QuestionBubble({
    required this.question,
    required this.tokens,
    required this.onSpeakerTap,
  });

  /// 题目状态。
  final _DevelopmentQuestion question;

  /// 当前主题色令牌。
  final AppTokens tokens;

  /// 点击音量图标时重播。
  final VoidCallback onSpeakerTap;

  @override
  Widget build(BuildContext context) {
    final isSpellingMeaning =
        question.kind == _DevelopmentQuestionKind.spellingMeaning;
    return _SystemBubbleContainer(
      tokens: tokens,
      wrong: question.showWrongFlash,
      playing: question.isPlaying,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onSpeakerTap,
            borderRadius: BorderRadius.circular(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(
                  child: _SoundWaveIcon(
                    key: const Key('development-question-speaker'),
                    playing: question.isPlaying,
                    size: DevelopmentLayout.voiceIconSize,
                  ),
                ),
                const SizedBox(width: DevelopmentLayout.voiceContentGap),
                _QuestionSlots(question: question, tokens: tokens),
              ],
            ),
          ),
          if (isSpellingMeaning && question.spellingSolved) ...[
            // 释义回填区：HTML 原型 `.meaning-results { margin-top: 11px;
            // padding-top: 10px; border-top: 1px solid var(--line); }`。
            // 之前 Flutter 用了 12px 间距、缺分隔线和 padding，这里整体迁回
            // 原型尺寸，让"拼对后展开的释义"看上去像从气泡里"切"出来的下半页。
            Container(
              margin: const EdgeInsets.only(
                top: DevelopmentLayout.meaningResultsMarginTop,
              ),
              padding: const EdgeInsets.only(
                top: DevelopmentLayout.meaningResultsPaddingTop,
              ),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: tokens.border,
                    width: DevelopmentLayout.meaningResultsBorderWidth,
                  ),
                ),
              ),
              child: _MeaningResults(question: question, tokens: tokens),
            ),
          ],
        ],
      ),
    );
  }
}

/// 系统消息气泡的通用外观，对应 HTML 原型 `.bubble`。
///
/// 错答时 `wrong=true` 会触发：
/// - shake：左右抖动 0.3s（HTML `@keyframes shake` 25%/75% ±4px）；
/// - wrongRing：从气泡边缘扩散的红光圈 0.55s（HTML `@keyframes wrongRing` scale 1→1.05, opacity 0.85→0）；
/// 三个反馈同时进行，但 shake 0.3s 先结束、ring 0.55s 后结束。
class _SystemBubbleContainer extends StatefulWidget {
  /// 创建系统气泡外壳。
  const _SystemBubbleContainer({
    required this.tokens,
    required this.child,
    this.wrong = false,
    this.playing = false,
  });

  /// 当前主题色令牌。
  final AppTokens tokens;

  /// 气泡内部内容。
  final Widget child;

  /// 是否显示错误反馈红色描边（true 时还会触发 shake + 红光扩散）。
  final bool wrong;

  /// 是否正在播放音频；播放时整条气泡点亮一圈主色光晕。
  final bool playing;

  @override
  State<_SystemBubbleContainer> createState() => _SystemBubbleContainerState();
}

class _SystemBubbleContainerState extends State<_SystemBubbleContainer>
    with TickerProviderStateMixin {
  /// 抖动控制器：错答时正向播一次 0.3s shake。
  late final AnimationController _shakeController;

  /// 红光扩散控制器：错答时正向播一次 0.55s wrongRing。
  late final AnimationController _ringController;

  /// 上一次 wrong 状态：用以在 wrong 由 true→false 时复位两个动画。
  bool _wasWrong = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: DevelopmentLayout.wrongShakeDuration,
    );
    _ringController = AnimationController(
      vsync: this,
      duration: DevelopmentLayout.wrongRingDuration,
    );
    _wasWrong = widget.wrong;
    if (widget.wrong) {
      _shakeController.forward(from: 0);
      _ringController.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant _SystemBubbleContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.wrong && !_wasWrong) {
      // 错答瞬时：触发一次完整反馈。
      _shakeController.forward(from: 0);
      _ringController.forward(from: 0);
    } else if (!widget.wrong && _wasWrong) {
      // 错答结束：立刻把两个动画归位。
      _shakeController.value = 0;
      _ringController.value = 0;
    }
    _wasWrong = widget.wrong;
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_shakeController, _ringController]),
      builder: (context, child) {
        // shake 包络：0→25% (-4px) →50%(0) →75%(+4px) →100%(0)
        // 实际是 [0, 0.25, 0.5, 0.75, 1] 对应 [0, -1, 0, 1, 0] 的归一值，
        // 乘以 wrongShakeDistance 4 得到真实像素位移。
        final st = _shakeController.value;
        double shakeOffset = 0;
        if (st < 0.25) {
          shakeOffset = -DevelopmentLayout.wrongShakeDistance * (st / 0.25);
        } else if (st < 0.5) {
          shakeOffset =
              -DevelopmentLayout.wrongShakeDistance * (1 - (st - 0.25) / 0.25);
        } else if (st < 0.75) {
          shakeOffset =
              DevelopmentLayout.wrongShakeDistance * ((st - 0.5) / 0.25);
        } else {
          shakeOffset =
              DevelopmentLayout.wrongShakeDistance * (1 - (st - 0.75) / 0.25);
        }

        Widget bubble = child!;
        if (widget.wrong) {
          // 红色扩散圈包住的是完整气泡边界，和内容保持一层隔离；它不
          // 会在气泡内部再画一圈，因此扬声器和字母不会被染红。
          bubble = Stack(
            clipBehavior: Clip.none,
            children: [
              bubble,
              Positioned.fill(
                child: IgnorePointer(
                  child: Transform.scale(
                    scale:
                        1 +
                        (DevelopmentLayout.wrongRingEndScale - 1) *
                            _ringController.value,
                    alignment: Alignment.center,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(
                            DevelopmentLayout.bubbleRadius,
                          ),
                          topRight: Radius.circular(
                            DevelopmentLayout.bubbleRadius,
                          ),
                          bottomRight: Radius.circular(
                            DevelopmentLayout.bubbleRadius,
                          ),
                          bottomLeft: Radius.circular(3),
                        ),
                        border: Border.all(
                          color: DevelopmentLayout.red.withValues(
                            alpha: .85 * (1 - _ringController.value),
                          ),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        return Transform.translate(
          offset: Offset(shakeOffset, 0),
          child: bubble,
        );
      },
      child: _buildBubble(widget.tokens),
    );
  }

  /// 实际构建气泡：错答时叠一层扩散红光圈 + 错误描边 + 红光晕。
  Widget _buildBubble(AppTokens tokens) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      constraints: const BoxConstraints(
        minHeight: DevelopmentLayout.bubbleMinHeight,
        minWidth: DevelopmentLayout.bubbleMinWidth,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: DevelopmentLayout.bubbleHorizontalPadding,
        vertical: DevelopmentLayout.bubbleVerticalPadding,
      ),
      decoration: BoxDecoration(
        // 所有系统气泡都使用统一的主题卡片色。消息是否处于当前答题状态，
        // 只影响内容和动画，不允许因为它从当前态变成历史态而突然换背景色。
        color: tokens.card,
        border: Border.all(
          color: widget.wrong
              ? DevelopmentLayout.wrongGlowLine
              : widget.playing
              ? DevelopmentLayout.voiceGlowLine
              : tokens.border,
          width: widget.wrong ? 2 : 1,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(DevelopmentLayout.bubbleRadius),
          topRight: Radius.circular(DevelopmentLayout.bubbleRadius),
          bottomRight: Radius.circular(DevelopmentLayout.bubbleRadius),
          bottomLeft: Radius.circular(3),
        ),
        boxShadow: [
          if (widget.wrong)
            BoxShadow(
              color: DevelopmentLayout.wrongGlowRing,
              blurRadius: 0,
              spreadRadius: 3,
            )
          else if (widget.playing)
            BoxShadow(
              color: DevelopmentLayout.voiceGlowRing,
              blurRadius: 0,
              spreadRadius: 3,
            )
          else
            BoxShadow(
              color: tokens.text.withValues(alpha: .04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
        ],
      ),
      // 内部只放原始内容。错误扩散圈在外层 Stack 绘制，避免 ring 落在
      // padding 内部，把扬声器和字母槽位误包成红色边框。
      child: widget.child,
    );
  }
}
