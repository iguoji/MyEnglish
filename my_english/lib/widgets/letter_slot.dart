// material.dart 提供绘制字母格所需的 Stack、Container 与文字能力。
import 'package:flutter/material.dart';

// 引入设计令牌，下划线的焦点光晕要用品牌蓝。
import '../common/theme.dart';
// 引入统一的闪烁光标：光标节奏与前后台停表由组件自己管理。
import 'blinking_caret.dart';

///
/// 「下划线字母格」的尺寸表。
///
/// 数值全部沿用 `ui/听音拼写1.html` 原型，原先住在
/// `lib/pages/spelling_reinforcement/widgets/spelling_layout.dart` 的
/// `spelling*` 一族常量，现在跟着组件搬到这里（值一个没改）。
/// 做法参照 `lib/widgets/qwerty_keyboard.dart` 与
/// `lib/widgets/pos_meaning_panel.dart`：公共组件自己维护尺寸。
///
abstract final class LetterSlotLayout {
  ///
  /// 单个字母区域的宽度；下划线和字母都在这个宽度内对齐。
  static const double letterWidth = 24;

  ///
  /// 单个字母区域高度，包含字母、下划线与闪烁光标。
  static const double letterHeight = 40;

  ///
  /// 相邻字母之间的水平间距，对应 HTML 的 `column-gap: 7px`。
  static const double letterGap = AppSpace.p2;

  ///
  /// 多行字母之间的垂直间距，对应 HTML 的 `row-gap: 10px`。
  static const double letterRunGap = AppSpace.p2;

  ///
  /// 字母字号，对应原型短词的视觉大小。
  static const double letterTextSize = AppFont.fs1;

  ///
  /// 字母下划线高度。
  ///
  /// 与 `PosMeaningPanelLayout.underlineHeight` 同值：这里填字母、那里填含义，
  /// 用户眼里是同一种「填空」，粗细不同会立刻看出是两套东西。改动请同步另一处。
  static const double underlineHeight = AppStroke.mark;

  ///
  /// 当前待输入下划线外围的淡蓝色焦点边框宽度。
  ///
  /// 作用是让用户一眼看出下一笔应该落在哪一条下划线上。
  /// 取值来由（为什么不是 2、也不是 4）见总表 [AppSize.underlineGlow]。
  static const double underlineFocusSpread = AppSize.underlineGlow;

  ///
  /// 当前待输入下划线焦点边框的透明度。
  ///
  /// 与词性及含义面板共用总表同一档 [AppAlpha.a10]，不再需要人工同步。
  static const double underlineFocusAlpha = AppAlpha.a10;

  ///
  /// 光标宽度，与词性及含义面板共用总表同一档。
  static const double caretWidth = AppSize.caretWidth;

  ///
  /// 光标高度：字母格的文字区高度也取这一档，字母底边与光标底边都对齐下划线。
  ///
  /// 总表值是字母字号（[letterTextSize]）的 2/3，光标只到字母三分之二高，
  /// 不再顶到字母顶部、也不会盖住 g / y 这类带尾巴字母的笔画。
  static const double caretHeight = AppSize.caretHeight;

  ///
  /// 字母与下划线之间留出的距离，避免字母下沿压在横线上。
  static const double letterBottomGap = AppSpace.p1;

  ///
  /// 新输入字母的完整动画时长。
  ///
  /// 动画分成「放大并显现」和「回落到正常大小」两段，使用较短时长，
  /// 让连续输入时字母能紧跟用户的按键节奏。
  static const int entryDurationMs = AppDuration.ms100;

  ///
  /// 新字母动画第一段的放大终点。
  static const double entryOvershootScale = 1.2;

  ///
  /// 新字母动画第一段所占的比例，剩余部分用于回落到正常大小。
  static const double entryOvershootPortion = 0.7;

  ///
  /// 「整词一次填入」时的动画时长（[LetterEntryStyle.reveal]）。
  ///
  /// 比敲键盘那一档略长，但字母**从一开始就看得见**，所以观感上更快：
  /// 敲键盘那档是从 scale 0 起手，一整词十几个字母同时从零放大时，
  /// 前几十毫秒屏幕上几乎是空的，会被读成「字母晚了一拍才出现」。
  static const int revealDurationMs = AppDuration.ms160;

  ///
  /// 揭示模式的起始缩放：从 0.88 轻轻长到 1，不做放大过冲。
  static const double revealStartScale = 0.88;

  ///
  /// 揭示模式里「淡入」占整段动画的比例：前 35% 就已经完全不透明。
  static const double revealFadePortion = 0.35;
}

///
/// 字母填入的两种节奏。
///
enum LetterEntryStyle {
  ///
  /// 敲键盘：从无到有猛地弹出（0 → 1.2 → 1），配合 26 键的按键手感。
  /// 拼写巩固逐字母输入用这一档。
  keystroke,

  ///
  /// 整词揭示：轻轻浮现（0.88 → 1，几乎立刻可见），一次填入整个单词也不会
  /// 出现「一整排字母同时从零放大」那种延迟感。看义选词答对候选后用这一档。
  reveal,
}

///
/// 一个带下划线、闪烁光标和入场动画的字母格。
///
/// 这是 `ui/听音拼写1.html` 中 `.slot` 的 Flutter 版本：字母格本身不画矩形
/// 边框，只保留底部下划线和当前位置的闪烁竖线，避免整排输入区看起来像一组
/// 占位输入框。
///
/// 拼写巩固用它接 26 键键盘的逐字母输入；看义选词用它显示「这条释义对应的
/// 单词」——选中正确候选后整词一次填入。两个模块共用同一个组件，用户看到的
/// 就是同一种填空。
///
class LetterSlot extends StatelessWidget {
  ///
  /// 创建一个字母格。
  const LetterSlot({
    required this.text,
    required this.isActive,
    required this.lineColor,
    required this.textColor,
    required this.entryToken,
    this.entryStyle = LetterEntryStyle.keystroke,
    super.key,
  });

  ///
  /// 当前显示的字母；空位为 null。
  final String? text;

  ///
  /// 是否是下一个等待填入的位置：会画焦点光晕和闪烁光标。
  final bool isActive;

  ///
  /// 下划线颜色，答错/答对时会统一变色。
  final Color lineColor;

  ///
  /// 已填入字母的颜色。
  final Color textColor;

  ///
  /// 这次填入对应的唯一编号；空位为 null。
  ///
  /// 该编号用于区分「同一个位置的新字母」和「之前已经显示过的字母」，
  /// 不依赖整轮重置控制器，因此首次输入与错误重试的表现完全一致。
  /// 恢复现场时传 null，不重放入场动画。
  final int? entryToken;

  ///
  /// 填入时用哪种节奏；默认是拼写巩固的敲键盘档。
  final LetterEntryStyle entryStyle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: LetterSlotLayout.letterWidth,
      height: LetterSlotLayout.letterHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 完全复刻 HTML：字母格不带矩形外框，只在底部保留独立横线。
          // 当前待输入的下划线额外带一圈淡蓝色扩散边框，提示输入位置，
          // 但边框只包住横线本身，不会把整个字母区域变成占位框。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: LetterSlotLayout.underlineHeight,
              decoration: BoxDecoration(
                color: lineColor,
                borderRadius: BorderRadius.circular(AppRadius.roundedPill),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: AppTokens.primary.withValues(
                            alpha: LetterSlotLayout.underlineFocusAlpha,
                          ),
                          blurRadius: AppShadow.none,
                          spreadRadius: LetterSlotLayout.underlineFocusSpread,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
          // 文字区域与下划线之间留出一点距离，避免字母下沿碰线。
          Positioned(
            left: 0,
            right: 0,
            bottom:
                LetterSlotLayout.underlineHeight +
                LetterSlotLayout.letterBottomGap,
            height: LetterSlotLayout.caretHeight,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: _buildLetterEntry(),
            ),
          ),
          if (isActive)
            Positioned(
              left:
                  (LetterSlotLayout.letterWidth - LetterSlotLayout.caretWidth) /
                  2,
              bottom:
                  LetterSlotLayout.underlineHeight +
                  LetterSlotLayout.letterBottomGap,
              // 光标是全 App 共用组件，自己管闪烁节奏和前后台停表；
              // 位置一移动，这里就换成新的一个，光标天然从「亮」开始。
              child: const BlinkingCaret(
                width: LetterSlotLayout.caretWidth,
                height: LetterSlotLayout.caretHeight,
              ),
            ),
        ],
      ),
    );
  }

  ///
  /// 构建字母本身的入场动画。
  ///
  /// 这里使用带唯一 key 的 `TweenAnimationBuilder`，而不是让同一个动画控制器
  /// 在「清空后再次输入」时反复复用。生活化解释：每次填入都发一张全新的入场
  /// 电影票，Flutter 就一定从第 0 帧开始播放，不会出现重试时只剩透明度变化。
  Widget _buildLetterEntry() {
    final text = this.text;
    if (text == null) return const SizedBox.shrink();

    final letter = Text(
      text,
      style: TextStyle(
        color: textColor,
        fontSize: LetterSlotLayout.letterTextSize,
        height: AppLine.lh1,
        fontWeight: AppWeight.semibold,
      ),
    );

    // 没有编号的内容属于恢复画面，不需要重新播放入场动画。
    if (entryToken == null) return letter;

    final isReveal = entryStyle == LetterEntryStyle.reveal;
    return TweenAnimationBuilder<double>(
      key: ValueKey(entryToken),
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(
        milliseconds: isReveal
            ? LetterSlotLayout.revealDurationMs
            : LetterSlotLayout.entryDurationMs,
      ),
      curve: isReveal ? Curves.easeOut : Curves.linear,
      builder: (context, progress, child) {
        if (isReveal) {
          // 揭示档：一上来就有可见的字母，只是从 0.88 轻轻长到 1。
          final start = LetterSlotLayout.revealStartScale;
          return Opacity(
            opacity: (progress / LetterSlotLayout.revealFadePortion).clamp(
              0.0,
              1.0,
            ),
            child: Transform.scale(
              alignment: Alignment.bottomCenter,
              scale: start + (1 - start) * progress,
              child: child,
            ),
          );
        }
        final overshootPortion = LetterSlotLayout.entryOvershootPortion;
        final scale = progress <= overshootPortion
            ? LetterSlotLayout.entryOvershootScale *
                  (progress / overshootPortion)
            : LetterSlotLayout.entryOvershootScale +
                  (1 - LetterSlotLayout.entryOvershootScale) *
                      ((progress - overshootPortion) / (1 - overshootPortion));
        final opacity = progress <= overshootPortion
            ? progress / overshootPortion
            : 1.0;

        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            // 缩放中心固定在字母区域的底部中心，和首次输入的视觉起点一致。
            alignment: Alignment.bottomCenter,
            scale: scale,
            child: child,
          ),
        );
      },
      child: letter,
    );
  }
}
