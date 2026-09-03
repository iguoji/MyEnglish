// material.dart 提供 Color 类型，布局文件中的颜色常量也因此保持类型明确。
import 'package:flutter/material.dart';

///
/// 「开发模块」演示页的布局尺寸表。
///
/// 顶部尺寸直接沿用听音辨义的页面规范，下面的聊天消息和键盘尺寸对应
/// `ui/聊天界面.html` 原型。把尺寸集中写在这里，后续调整时不会需要在
/// 多个组件里逐个寻找数字。
///
abstract final class DevelopmentLayout {
  /// 页面左右的统一留白。
  static const double pageInset = 20;

  /// 顶栏距离安全区顶部的距离。
  static const double headerTop = 18;

  /// 返回按钮与顶部中央进度数字共用的固定点击画布。
  static const double headerButtonSize = 34;

  /// 右上角计时文字字号，与听音辨义保持一致。
  static const double headerTimerTextSize = 15;

  /// 顶栏与进度条之间的间距。
  static const double progressTop = 10;

  /// 进度条高度。
  static const double progressHeight = 4;

  /// 进度条未填充轨道的颜色，对应原型 `#e8edf3`。
  static const progressTrack = Color(0xFFE8EDF3);

  /// 聊天区域的内边距，对应原型 `.chat { padding: 20px; }`。
  static const double chatInset = 20;

  /// 消息之间的垂直间隔。
  static const double messageGap = 14;

  /// 气泡最小高度，对应原型 `.bubble { min-height: 46px; }`。
  static const double bubbleMinHeight = 46;

  /// 气泡最小宽度。
  ///
  /// 生活化解释：像 `iii` 这样的短错误答案也要保留一个正常气泡的
  /// 呼吸空间，不能因为文字少就缩成一小块。系统消息和用户消息统一使用
  /// 这个下限，避免两类消息的视觉比例不一致。
  static const double bubbleMinWidth = 64;

  /// 气泡内部的水平留白。
  static const double bubbleHorizontalPadding = 13;

  /// 气泡内部的垂直留白。
  static const double bubbleVerticalPadding = 11;

  /// 气泡圆角。
  static const double bubbleRadius = 15;

  /// 题目气泡中的音量按钮尺寸。
  static const double voiceIconSize = 23;

  /// 题目气泡中音量图标与圆点之间的距离。
  static const double voiceContentGap = 10;

  /// 答题区顶部边线与内部留白。
  static const double answerPanelInset = 20;

  /// 答题选项之间的间隔。
  static const double choiceGap = 8;

  /// 选项最小高度，对应原型 `.choice { height: 42px; }`。
  static const double choiceHeight = 42;

  /// 选项左侧 A/B/C/D 标记的边长。
  static const double choiceBadgeSize = 22;

  /// 选项文字字号。
  static const double choiceTextSize = 14;

  /// 键盘按键之间的水平间隔。
  static const double keyGap = 5;

  /// 键盘行之间的垂直间隔。
  static const double keyRowGap = 7;

  /// 键盘按键高度。
  static const double keyHeight = 38;

  /// 键盘按键圆角。
  static const double keyRadius = 7;

  /// 键盘文字字号。
  static const double keyTextSize = 13;

  // ====== 槽位相关尺寸（HTML 原型 .slot）======
  /// 空槽位圆点的直径，对应原型 `.slot.dot:after` 的 5×5。
  static const double slotDotSize = 5;

  /// 字母槽位的固定高度（=圆点垂直居中区域），对应原型 `.slot { height: 20px; }`。
  static const double slotHeight = 20;

  /// 字母槽位宽度，对应原型 `.slot.letter { width: 13px; }`。
  static const double slotLetterWidth = 13;

  /// 槽位之间的水平间距。
  static const double slotGap = 4;

  /// 圆点动画完整周期，对应 HTML 原型 `@keyframes dot .72s`。
  ///
  /// 加载气泡、语音消息和拼写槽位统一读取这一节拍，避免同一页面里出现
  /// 看起来不一致的圆点动画。
  static const Duration dotAnimationDuration = Duration(milliseconds: 720);

  /// 语音消息圆点之间的错开时间，对应原型 `animation-delay: 75ms`。
  static const double dotAnimationDelayMs = 75;

  /// 拼写槽位圆点之间的错开时间，对应原型 `animation-delay: 60ms`。
  static const double slotDotAnimationDelayMs = 60;

  /// 圆点亮起时的最大放大比例，对应原型 `transform: scale(1.25)`。
  static const double dotAnimationPeakScale = 1.25;

  /// 语音/题目播放时的浅蓝描边，对应原型 `--glow-line: #6da6df`。
  static const voiceGlowLine = Color(0xFF6DA6DF);

  /// 语音/题目播放时的外圈光晕，对应原型 `--glow-ring: #206bc418`。
  static const voiceGlowRing = Color(0x18206BC4);

  /// 槽位字母字号与字重，对应原型 `.letter-layer { font-size: 15px; font-weight: 800; }`。
  static const double slotLetterSize = 15;

  // ====== 释义回填区尺寸（HTML 原型 .meaning-results / .pos-group / .meaning-chip）======

  /// 释义回填区与气泡内其他内容的间距，对应原型 `.meaning-results { margin-top: 11px; }`。
  static const double meaningResultsMarginTop = 10;

  /// 释义回填区上沿内边距 + 顶部分隔线 1px：原型的 10px padding-top + 1px border。
  /// 实际实现用 `Container(decoration:border-top, padding:top:10)`，下面用此值。
  static const double meaningResultsPaddingTop = 12;

  /// 释义回填区分隔线粗细。
  static const double meaningResultsBorderWidth = 1;

  /// 词性 (pos.) 列的固定宽度，对应原型 `.pos-group { grid-template-columns: 38px 1fr; }`。
  static const double posColumnWidth = 38;

  /// 词性列与含义 chip 之间的间距。
  static const double posGroupGap = 2;

  /// 词性文字字号与字重；使用页面常规的小正文尺寸，不再显得过于细小。
  static const double posTextSize = 14;

  /// 词性文字相对本组第一行含义的顶部偏移，让文字视觉上处于首行垂直居中位置。
  static const double posTextMarginTop = 4;

  /// 释义 chip 最小宽度，对应原型 `.meaning-chip { min-width: 54px; }`。
  static const double meaningChipMinWidth = 54;

  /// 释义 chip 高度，对应原型 `.meaning-chip { height: 22px; }`。
  static const double meaningChipHeight = 28;

  /// 释义 chip 水平内边距，在当前基础上再增加 2px，让“待选择”和已选释义
  /// 的文字都与容器边缘保持更舒适的距离。
  static const double meaningChipHorizontalPadding = 12;

  /// 释义 chip 圆角，对应原型 `.meaning-chip { border-radius: 6px; }`。
  static const double meaningChipRadius = 6;

  /// 释义 chip 字号与字重。
  ///
  /// 含义是这道题拼写完成后需要辨认的中文内容。把字号从 11px 调到 13px，
  /// 让较长的中文释义也能更容易看清，不需要用户额外放大页面。
  static const double meaningChipTextSize = 13;

  /// 含义 chip 在同一行之间的水平间距，比原来增加 2px。
  static const double meaningChipSpacing = 10;

  /// 含义 chip 换行时的垂直间距，比原来增加 2px。
  static const double meaningChipRunSpacing = 10;

  // ====== 阶段提示与错误折叠组（HTML 原型 .phase-float / .err-stack）======

  /// "选择含义 1/N" 阶段提示字号。
  static const double phaseFloatTextSize = 12;

  /// 阶段提示距答题面板的垂直距离。
  ///
  /// 原型 `.phase-float { top: -24px; }`（向上偏离面板 24px）。
  /// 之前 Flutter 用了 8px，提示离面板太近不像"浮在外"。
  static const double phaseFloatGap = 8;

  /// 阶段提示的浮动文字行高，用于把文字放在面板上沿之外。
  static const double phaseFloatLineHeight = 14;

  /// 错误折叠组的"展开 N 条"脚注字号，对应原型 `.err-foot { font-size: 11px; }`。
  static const double errFootTextSize = 11;

  /// 错误折叠组"叠层阴影"水平偏移（向内收），对应原型 `.err-stack::before { right: 9px; }`。
  static const double errStackShadowInset = 9;

  /// 错误折叠组"叠层阴影"上沿露出的高度，对应原型 `top: -5px`。
  static const double errStackShadowTop = -5;

  /// 错误折叠组数量牌 18×18（HTML 原型 `.err-num`）。
  static const double errBadgeSize = 18;

  // ====== 错答反馈动画（HTML 原型 .quiz-bubble.wrong / .shake / .wrongRing）======

  /// 错答时题目气泡左右抖动的最大位移，对应原型 `@keyframes shake` 25%/75% 时的 4px。
  static const double wrongShakeDistance = 4;

  /// 错答时题目气泡抖动动画时长，对应原型 0.3s ease。
  static const Duration wrongShakeDuration = Duration(milliseconds: 300);

  /// 错答时整圈红光扩散的时长，对应原型 0.55s ease-out。
  static const Duration wrongRingDuration = Duration(milliseconds: 550);

  /// 错答时红光最终放大的倍数，对应原型 `transform: scale(1.05)`。
  static const double wrongRingEndScale = 1.05;

  /// 错误消息的红色。
  static const red = Color(0xFFD63939);

  /// 错误题目播放反馈的描边，对应原型 `--glow-line: #c92a2a`。
  static const wrongGlowLine = Color(0xFFC92A2A);

  /// 错误题目播放反馈的外圈光晕，对应原型 `--glow-ring: #c92a2a28`。
  static const wrongGlowRing = Color(0x28C92A2A);

  /// 错误消息浅色背景。
  static const redLight = Color(0xFFFCEAEA);

  /// 错误消息叠层阴影的"实色"浅红，对应 HTML 原型 `.err-stack::before` 的 #f6c9c9。
  /// 注意：HTML 用的是实色不透明浅红，Flutter 之前用 alpha 0.16 太淡、几乎看不到"叠层"
  /// 暗示，所以这里改回实色。
  static const redStackShadow = Color(0xFFF6C9C9);

  /// 成功消息使用的绿色。
  static const green = Color(0xFF2FB344);

  /// 成功消息中的白色圆形勾选底。
  static const checkCircleSize = 19.0;

  /// 槽位圆点的浅蓝色（HTML 原型 `--dot` 默认值 #9bbce0），与 accent 拉开层次，
  /// 不会把"还没字母"的状态染得太重。深色模式用同一个值即可，圆点本身已经很浅。
  static const slotDot = Color(0xFF9BBCE0);

  /// 槽位字母的发光阴影（HTML 原型 `text-shadow: 0 0 8px rgba(32,107,196,.22)`）。
  /// 固定 const：与 accent 同步维护代价大、收益小，单独维护一份可读性更高。
  /// ARGB 0x38 = 56/255 ≈ 22% 透明度。
  static const slotLetterGlow = Color(0x38206BC4);

  /// "未答"释义 chip 的浅灰描边，对应 HTML 原型 `.meaning-blank` 的 1px dashed。
  static const meaningBlankBorder = Color(0xFFABB7C6);

  /// "未答"释义 chip 的占位文字色，对应 HTML 原型 `.meaning-blank` 的 #9aa6b5。
  static const meaningBlankText = Color(0xFF9AA6B5);

  /// 等待中三个"正在输入"圆点的颜色。
  /// HTML 原型等待中圆点用 `var(--dot)` = #9bbce0，与声波圆点保持一致；
  /// Flutter 之前用了 accent.alpha .55，会让等待气泡过于"鲜亮"，改成浅蓝。
  static const typingDot = Color(0xFF9BBCE0);
}
