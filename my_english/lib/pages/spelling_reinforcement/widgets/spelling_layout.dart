///
/// 拼写巩固页面的布局尺寸表。
///
/// 把边距、圆角、按键尺寸等“会经常调整的设计数字”集中在一处，
/// 后续改样式不用到多层 Widget 里翻找。
///
/// 数值来源分两类，改动时请勿混淆：
/// 1. 顶栏返回图标、中间数字进度与进度条——刻意复刻听音辨义与词义连连，
///    让三个复习模块切换时顶部完全不跳动，用户感觉是同一套产品；
/// 2. 其余全部——复刻 `ui/拼写巩固.html` 原型，注释中标注了对应的 CSS 值。
///
/// 唯一刻意偏离原型的是键盘按键高度：原型是 34×34，低于 44 像素的最小触控
/// 尺寸，手指在真机上很容易点错相邻键，因此这里抬到 44。
///
abstract final class SpellingLayout {
  ///
  /// 页面左右统一留白（原型 `--app-px: 20px`，同时也是另两个模块的 pageInset）。
  static const double pageInset = 20;

  ///
  /// 顶栏距离安全区（刘海/状态栏）顶部的距离。
  ///
  /// 取听音辨义的 18 而不是原型的 16，三个模块顶栏才能严丝合缝对齐。
  static const double headerTop = 18;

  ///
  /// 顶栏图标按钮（返回键）的点击画布大小。
  ///
  /// 生活化解释：这是一个 34×34 的不可见方块，手指点在里面任意位置都能触发按钮。
  static const double headerButtonSize = 34;

  ///
  /// 顶栏返回图标的字号（与另两个模块完全一致）。
  static const double headerIconSize = 21;

  ///
  /// 中间「第几个 / 总数」的字号（与另两个模块的数字进度一致）。
  static const double headerProgressTextSize = 16;

  ///
  /// 顶栏与下方进度条之间的纵向间距（与另两个模块一致）。
  static const double progressTop = 10;

  ///
  /// 进度条高度（原型 `height: 3px`）。
  static const double progressHeight = 3;

  ///
  /// 进度条圆角（原型 `border-radius: 2px`）。
  static const double progressRadius = 2;

  ///
  /// 进度条与下方主体之间的距离（原型 `main` 的 `py-3`）。
  static const double bodyVerticalInset = 12;

  ///
  /// 模式徽标与下方词义之间的距离（原型 `#mode-badge` 的 `mb-2`）。
  static const double badgeBottomGap = 8;

  ///
  /// 模式徽标的左右内边距（Tabler `.badge` 的横向 padding）。
  static const double badgePaddingHorizontal = 8;

  ///
  /// 模式徽标的上下内边距（Tabler `.badge` 的纵向 padding）。
  static const double badgePaddingVertical = 4;

  ///
  /// 模式徽标圆角（Tabler `.badge { border-radius: 4px }`）。
  static const double badgeRadius = 4;

  ///
  /// 模式徽标文字字号（Tabler `.badge` 的 0.75rem）。
  static const double badgeTextSize = 12;

  ///
  /// 词性标签列固定宽度，用于让多条含义中的词性纵向严格对齐。
  ///
  /// 生活化解释：每条含义都从同一根竖线开始写词性（n. / vt. …），
  /// 词性不论长短都在同一列，右边解释整体整齐成一条边。
  static const double posColumnWidth = 48;

  ///
  /// 词性列与中文释义之间的水平间距。
  static const double posMeaningGap = 8;

  ///
  /// 相邻两条含义之间的纵向间距。
  static const double meaningRowGap = 6;

  ///
  /// 含义区中词性标签的文字字号。
  ///
  /// 生活化解释：词性（n. / vt.）只是分类小标签，视觉要轻，不能和正文抢注意力。
  static const double meaningPosTextSize = 12.5;

  ///
  /// 含义区中词性标签与释义正文共用的字号。
  ///
  /// 生活化解释：比原来单条「词义提示」稍微小一点，让后移的含义区作为补充说明，
  /// 不要喧宾夺主地盖过上方的占位格。
  static const double meaningTextSize = 14;

  ///
  /// 占位格与下方含义区之间的距离（原型 `#slot-row` 的 `mb-4`）。
  static const double meaningBottomGap = 16;

  ///
  /// 含义区与下方作答区之间的距离。
  static const double slotBottomGap = 24;

  ///
  /// 片段占位格的最小宽度（原型 `.slot { min-width: 48px }`）。
  static const double slotMinWidth = 48;

  ///
  /// 片段占位格的高度（原型 `.slot { height: 48px }`）。
  static const double slotHeight = 48;

  ///
  /// 片段占位格的左右内边距（原型 `.slot { padding: 0 8px }`）。
  static const double slotPaddingHorizontal = 8;

  ///
  /// 字母占位格的固定边长（原型 `.slot.letter-slot { width/height: 40px }`）。
  static const double letterSlotSize = 40;

  ///
  /// 占位格圆角（原型 `.slot { border-radius: 10px }`）。
  static const double slotRadius = 10;

  ///
  /// 占位格边框宽度（原型 `border: 1.5px`）。
  static const double slotBorderWidth = 1.5;

  ///
  /// 占位格之间的间距（原型 `.slot-row { gap: 8px }`）。
  static const double slotGap = 8;

  ///
  /// 占位格内文字字号（原型 `.slot { font-size: 1.05rem }`）。
  static const double slotTextSize = 17;

  ///
  /// 候选片段按钮的最小高度（原型 `.chunk-btn { min-height: 44px }`）。
  static const double chunkMinHeight = 44;

  ///
  /// 候选片段按钮的最小宽度（原型 `.chunk-btn { min-width: 52px }`）。
  static const double chunkMinWidth = 52;

  ///
  /// 候选片段按钮的左右内边距（原型 `padding: 6px 14px` 的横向部分）。
  static const double chunkPaddingHorizontal = 14;

  ///
  /// 候选片段按钮圆角（原型 `.chunk-btn { border-radius: 10px }`）。
  static const double chunkRadius = 10;

  ///
  /// 候选片段文字字号（原型 `.chunk-btn { font-size: 1rem }`）。
  static const double chunkTextSize = 16;

  ///
  /// 候选片段之间的间距（原型候选区 `gap-2`）。
  static const double chunkGap = 8;

  ///
  /// 已用候选片段的不透明度（原型 `.chunk-btn.used { opacity: .35 }`）。
  static const double chunkUsedOpacity = 0.35;

  ///
  /// 键盘按键高度。
  ///
  /// 刻意偏离原型的 34：那个尺寸低于 44 像素的最小触控标准，真机上手指
  /// 很容易点到相邻键。同一份原型里的候选片段按钮用的就是 44。
  static const double keyHeight = 44;

  ///
  /// 普通字母键的最大宽度（原型 `.kb-key { max-width: 34px }`）。
  static const double keyMaxWidth = 34;

  ///
  /// 退格等功能键的最大宽度（原型 `.kb-key.fn { max-width: 46px }`）。
  static const double functionKeyMaxWidth = 46;

  ///
  /// 键盘按键圆角（原型 `.kb-key { border-radius: 8px }`）。
  static const double keyRadius = 8;

  ///
  /// 键盘按键文字字号（原型 `.kb-key { font-size: .95rem }`）。
  static const double keyTextSize = 15;

  ///
  /// 同一行按键之间的间距（原型 `.kb-row { gap: 6px }`）。
  static const double keyGap = 6;

  ///
  /// 键盘相邻两行之间的间距（原型键盘容器的 `gap-2`）。
  static const double keyRowGap = 8;

  ///
  /// 手动拆分时单个字母的宽度（原型 `.split-letter { width: 36px }`）。
  static const double splitLetterWidth = 36;

  ///
  /// 手动拆分条的行高（原型 `.split-letter { height: 36px }`）。
  static const double splitRowHeight = 36;

  ///
  /// 手动拆分字母字号（原型 `.split-letter { font-size: 1.05rem }`）。
  static const double splitLetterTextSize = 17;

  ///
  /// 字母之间可点击的“剪口”宽度（原型 `.split-gap { width: 18px }`）。
  static const double splitGapWidth = 18;

  ///
  /// 剪口内斜线图标的字号（原型 `.split-gap i { fs-4 }`）。
  static const double splitGapIconSize = 14;

  ///
  /// 选中剪口时图标的放大倍数（原型 `.split-gap.active i { scale(1.2) }`）。
  static const double splitGapActiveScale = 1.2;

  ///
  /// 手动拆分区内各块之间的距离（原型手动拆分容器的 `gap-3`）。
  static const double splitSectionGap = 12;

  ///
  /// 手动拆分说明文字字号（原型 `small`）。
  static const double splitTipTextSize = 12;

  ///
  /// 底部工具按钮的边长（原型 `.tool-btn { width/height: 40px }`）。
  static const double toolButtonSize = 40;

  ///
  /// 工具按钮圆角（原型 `.tool-btn { border-radius: 10px }`）。
  static const double toolButtonRadius = 10;

  ///
  /// 工具按钮内 Tabler 图标的字号（原型 `fs-3`）。
  static const double toolIconSize = 20;

  ///
  /// 两个工具按钮之间的间距（原型工具条 `gap-2`）。
  static const double toolButtonGap = 8;

  ///
  /// 底部工具条与屏幕安全区之间额外保留的距离。
  ///
  /// 生活化解释：确保「刷新拆分」和「手动拆分」两个工具按钮不会贴着屏幕底部
  /// 的系统手势条或导航区，单手点击时更从容、不会误触首页手势。
  static const double toolBarBottomGap = 12;

  ///
  /// 工具条与上方作答区之间的距离（原型工具条 `pt-3`）。
  static const double toolBarTop = 16;

  ///
  /// 答错反馈的抖动时长（原型 `shake .35s`）。
  static const int shakeDurationMs = 350;

  ///
  /// 答错抖动各关键帧的左右位移（原型 `shake` 的 0/20/40/60/80/100%）。
  ///
  /// 生活化解释：卡片先往左甩 4 像素、再往右 4 像素，来回两次后停回原位，
  /// 像被人捏住摇了摇头说“不对”。
  static const List<double> shakeKeyframes = <double>[0, -4, 4, -4, 4, 0];

  ///
  /// 填对一格时的弹入动画时长（原型 `popIn .25s`）。
  static const int popDurationMs = 250;

  ///
  /// 弹入动画的最大放大倍数（原型 `popIn` 60% 处的 `scale(1.06)`）。
  static const double popMaxScale = 1.06;

  ///
  /// 弹入动画起始的缩小倍数（原型 `popIn` 0% 处的 `scale(.85)`）。
  static const double popMinScale = 0.85;

  ///
  /// 作答区切换时的淡入时长（原型 `.fade-switch` 的 `fadeIn .25s`）。
  static const int fadeDurationMs = 250;

  ///
  /// 淡入时作答区从下方上移的距离（原型 `translateY(4px)` → `translateY(0)`）。
  static const double fadeSlideOffset = 4;

  ///
  /// 一个单词拼完后切到下一个词的停顿（原型 `setTimeout(..., 500)`）。
  ///
  /// 这段时间里输入被锁住，让用户看清最后一格变绿再翻页。
  static const int wordAdvanceDelayMs = 500;

  ///
  /// 自动揭示答案后停留的时间。
  ///
  /// 比拼对的停顿长一倍：这一刻正是「想不起来 → 看到正确答案」的记忆强化点，
  /// 翻页太快等于没揭示。
  static const int revealDelayMs = 1200;

  ///
  /// 进入单词后自动发音的延迟（原型 `setTimeout(speakCurrent, 350)`）。
  static const int autoSpeakDelayMs = 350;

  ///
  /// 结算页左右留白（原型行内 `padding-left/right: 50px`）。
  static const double summaryInset = 50;

  ///
  /// 结算页三大块（头部、统计、按钮）之间的间距（原型 `gap-4` = 1.5rem）。
  static const double summarySectionGap = 24;

  ///
  /// 结算页顶部圆形图标底盘直径（原型 `avatar avatar-xl` = 4rem）。
  static const double summaryAvatarSize = 64;

  ///
  /// 结算页圆形底盘内的 Tabler 图标字号（原型 `fs-1` = 1.5rem）。
  static const double summaryAvatarIconSize = 24;

  ///
  /// 结算页主标题字号（原型 `fs-1` = 1.5rem）。
  static const double summaryTitleSize = 24;

  ///
  /// 结算页副标题字号（原型 `small`）。
  static const double summarySubtitleSize = 12;

  ///
  /// 结算页 2×2 统计卡之间的间距（原型 `row g-2` = 0.5rem）。
  static const double summaryStatGap = 8;

  ///
  /// 结算页统计卡上下内边距（原型 `py-3` = 1rem）。
  static const double summaryStatPaddingVertical = 16;

  ///
  /// 结算页统计卡圆角（原型 `.card` 与候选按钮同为 10）。
  static const double summaryStatRadius = 10;

  ///
  /// 结算页统计卡标题字号（原型 `small`）。
  static const double summaryStatLabelSize = 12;

  ///
  /// 结算页统计卡标题左侧图标字号（与词义连连结算页一致）。
  static const double summaryStatIconSize = 13;

  ///
  /// 结算页统计卡主数值字号（原型 `display-6`）。
  static const double summaryStatValueSize = 40;

  ///
  /// 结算页“用时”这一格的数值字号（原型 `fs-1`，因为 00:00 比纯数字长）。
  static const double summaryStatTimeSize = 24;

  ///
  /// 结算页统计卡底部单位说明字号（原型 `text-xs`）。
  static const double summaryStatUnitSize = 10;

  ///
  /// 结算页底部按钮高度（原型 `btn py-2 fs-3` 的实际渲染高度）。
  static const double summaryButtonHeight = 46;

  ///
  /// 结算页底部按钮文字字号（与词义连连结算页按钮一致）。
  static const double summaryButtonTextSize = 14;

  ///
  /// 「需加强」单词标签的左右内边距。
  static const double weakChipPaddingHorizontal = 8;

  ///
  /// 「需加强」单词标签的上下内边距。
  static const double weakChipPaddingVertical = 4;

  ///
  /// 「需加强」单词标签圆角（与徽标一致）。
  static const double weakChipRadius = 4;

  ///
  /// 「需加强」单词标签文字字号。
  static const double weakChipTextSize = 12;

  ///
  /// 「需加强」标签之间的间距。
  static const double weakChipGap = 6;
}
