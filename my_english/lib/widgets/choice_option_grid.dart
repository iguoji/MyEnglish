import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../common/theme.dart';

/// 听音辨义、看义选词共用四选项：两列等宽、同一套对错状态与反馈。
/// 选项已经由题目服务排序，本组件只负责显示，不重新打乱或判断答案。
///
/// 字号是**全站统一**的 14 号半粗（`fs5Semibold`），与结算页底部那两颗按钮
/// 同一档。两个模块的候选一律走这一档，不提供按模块改字号的开关：同一种卡片
/// 在两个页面里长得不一样，本身就是缺陷。文字太长时由内部的 FittedBox 等比
/// 缩小，不换行、不撑高卡片。
class ChoiceOptionGrid extends StatefulWidget {
  const ChoiceOptionGrid({
    required this.options,
    required this.questionKey,
    required this.onTap,
    required this.keyPrefix,
    this.wrong = const <String>{},
    this.correct = const <String>{},
    this.enabled = true,
    super.key,
  });

  final List<String> options;

  /// 当前题目的身份；即使下一题碰巧有相同候选，也要使用不同标识。
  /// 只用于隔开两道题的点击，不参与题目保存或答案判断。
  final Object questionKey;
  final Set<String> wrong;
  final Set<String> correct;
  final ValueChanged<String> onTap;
  final String keyPrefix;
  final bool enabled;

  @override
  State<ChoiceOptionGrid> createState() => _ChoiceOptionGridState();
}

class _ChoiceOptionGridState extends State<ChoiceOptionGrid> {
  /// 新题显示后，等手指全部松开并安静一小会儿，再开始接受答案。
  /// 每一次连点都会重新计时，避免固定倒计时结束后又接到同一串连点。
  static const _quietPeriod = Duration(milliseconds: AppDuration.ms350);

  final Set<int> _pressedPointers = <int>{};
  Timer? _unlockTimer;
  bool _waitingForQuiet = false;
  int _inputGeneration = 0;

  bool get _canInteract => widget.enabled && !_waitingForQuiet;

  @override
  void didUpdateWidget(covariant ChoiceOptionGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.questionKey == oldWidget.questionKey &&
        listEquals(widget.options, oldWidget.options)) {
      return;
    }
    _inputGeneration++;
    // 第一份候选就位时直接可用；换题时才需要拦住上一串点击。
    if (oldWidget.options.isEmpty) return;
    _waitingForQuiet = true;
    _scheduleUnlock();
  }

  void _scheduleUnlock() {
    _unlockTimer?.cancel();
    // 按住旧题跨过换题时刻也不能作答；必须先抬手，之后才开始这段安静期。
    if (_pressedPointers.isNotEmpty) return;
    _unlockTimer = Timer(_quietPeriod, () {
      if (!mounted) return;
      setState(() => _waitingForQuiet = false);
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    _pressedPointers.add(event.pointer);
    if (_waitingForQuiet) _unlockTimer?.cancel();
  }

  void _onPointerEnd(PointerEvent event) {
    _pressedPointers.remove(event.pointer);
    if (_waitingForQuiet) _scheduleUnlock();
  }

  void _tap(int generation, String text) {
    // 手势可能在旧题按下、在新题抬起；旧回调也必须在这里作废。
    if (!_canInteract || generation != _inputGeneration) return;
    widget.onTap(text);
  }

  @override
  void dispose() {
    _unlockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    final generation = _inputGeneration;
    if (options.isEmpty) return const SizedBox.shrink();
    assert(options.length == 4, '选择题必须有四个候选');
    return Listener(
      // 放在点击屏障外面，保护期间也能感知连点，从最后一次抬手重新计时。
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: AbsorbPointer(
        absorbing: !_canInteract,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.pBase,
            AppSpace.p0,
            AppSpace.pBase,
            AppSpace.pBase,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (var row = 0; row < 2; row++) ...<Widget>[
                if (row > 0) const SizedBox(height: AppSpace.p2),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      for (var column = 0; column < 2; column++) ...<Widget>[
                        if (column > 0) const SizedBox(width: AppSpace.p2),
                        Expanded(
                          child: _ChoiceOption(
                            // 生活化解释：key 只认「第几号位」，不认「上面写了什么字」。
                            // 以前 key 里带着候选词文本，换一小题文本就变了，四张卡会被
                            // 整块销毁再重建——看起来就是「整屏闪一下」，而不是原地更新。
                            // 固定成按位置编号后，卡片本体（描边、底色）留在原地，
                            // 变的只有里面的文字，换题才有连续的过渡。
                            key: ValueKey<String>(
                              '${widget.keyPrefix}-${row * 2 + column}',
                            ),
                            index: row * 2 + column,
                            text: options[row * 2 + column],
                            wrong: widget.wrong.contains(
                              options[row * 2 + column],
                            ),
                            correct: widget.correct.contains(
                              options[row * 2 + column],
                            ),
                            enabled: _canInteract,
                            onTap: () =>
                                _tap(generation, options[row * 2 + column]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceOption extends StatelessWidget {
  const _ChoiceOption({
    required this.index,
    required this.text,
    required this.wrong,
    required this.correct,
    required this.enabled,
    required this.onTap,
    super.key,
  });
  final int index;
  final String text;
  final bool wrong;
  final bool correct;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: AppDuration.ms160);
    final optionLabel = String.fromCharCode(65 + index);
    final feedbackColor = correct
        ? AppTokens.success
        : wrong
        ? AppTokens.danger
        : null;

    // 状态图标混入少量正文色：浅色主题略压深，深色主题略提亮，保持小图标清晰。
    final feedbackForeground = feedbackColor == null
        ? tokens.textSecondary
        : Color.alphaBlend(
            tokens.text.withValues(alpha: AppAlpha.a20),
            feedbackColor,
          );
    // 错项用次要文字色表达「已经排除」，仍然保留完整、可读的候选内容。
    // 红绿仅出现在右侧图标上，卡面和外框统一保持中性色。
    final style = textTheme.fs5Semibold.copyWith(
      color: wrong && !correct ? tokens.textSecondary : tokens.text,
    );
    return Semantics(
      // 图标替换字母后，读屏仍保留选项序号，并能读出对错，不仅靠颜色传达结果。
      label: optionLabel,
      value: correct
          ? '回答正确'
          : wrong
          ? '回答错误'
          : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled && !wrong && !correct ? onTap : null,
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSize.touchTarget),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.p3,
              vertical: AppSpace.p2,
            ),
            decoration: BoxDecoration(
              color: tokens.card,
              borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              border: Border.all(color: tokens.rowBorder),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  // 换词时让新旧文字在同一格里交叉淡入淡出：这就是「原地更新」和
                  // 「整块被换掉」的区别。文字本身仍然只占一行，放不下就由下面的
                  // FittedBox 等比缩小，不会换行把卡片撑高。
                  child: AnimatedSwitcher(
                    duration: duration,
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    // 默认的 Stack 是居中对齐的；候选词靠左排，这里显式改成左对齐，
                    // 否则英文短词会在切换的一瞬间左右跳一下。
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      // `?current` 是空感知元素：current 为空时这一项直接不出现。
                      children: <Widget>[...previous, ?current],
                    ),
                    child: FittedBox(
                      // key 只挂文本：同一格里的文字换了才重放淡入。
                      key: ValueKey<String>(text),
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(text, maxLines: 1, style: style),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.p2),
                // 序号退到右端做辅助标记，答题后原位换成无底盘、无外框的 Tabler 图标。
                // 这一格始终预留相同空间：长词不会在选中时突然缩小，正文也不会跳动。
                SizedBox(
                  width: AppIcon.i20,
                  height: AppSize.optionBadge,
                  child: ExcludeSemantics(
                    child: AnimatedSwitcher(
                      duration: duration,
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: feedbackColor == null
                          ? Text(
                              optionLabel,
                              key: const ValueKey<String>('label'),
                              style: textTheme.fs6Bold.copyWith(
                                color: tokens.textSecondary,
                              ),
                            )
                          : Icon(
                              correct ? AppGlyph.correct : AppGlyph.wrong,
                              key: ValueKey<String>(
                                correct ? 'correct' : 'wrong',
                              ),
                              size: AppIcon.i20,
                              color: feedbackForeground,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
