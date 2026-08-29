///
/// 看义选词页面的布局尺寸表：集中声明页面用到的间距、圆角等数值常量。
///
/// 顶栏返回图标、中间数字进度与进度条，刻意和听音辨义保持完全一致，
/// 使四个复习模块切换时顶部严丝合缝、不产生任何跳动。
/// 其余区域的数值等玩法落地后再补充。
///
abstract final class MeaningWordChoiceLayout {
  ///
  /// 页面左右的统一留白，与听音辨义一致。
  static const double pageInset = 20;

  ///
  /// 顶栏距离安全区（刘海/状态栏）顶部的距离，与听音辨义一致。
  static const double headerTop = 18;

  ///
  /// 返回按钮与右侧占位区共用的固定宽高，与听音辨义一致。
  ///
  /// 生活化解释：这是一个 34×34 的不可见点击方块，手指点在方块内任意
  /// 位置都能触发返回，比图标本身大一圈，好按很多。
  static const double headerButtonSize = 34;

  ///
  /// 顶栏返回图标的字号，与听音辨义一致。
  static const double headerIconSize = 21;

  ///
  /// 中间「第几个 / 总数」数字进度的字号，与听音辨义一致。
  static const double headerProgressTextSize = 16;

  ///
  /// 顶栏与下方进度条之间的纵向间距，与听音辨义一致。
  static const double progressTop = 10;

  ///
  /// 页面进度条的固定高度，与听音辨义一致（4 像素）。
  static const double progressHeight = 4;

  ///
  /// 进度条两端的圆角，与听音辨义一致。
  static const double progressRadius = 2;

  ///
  /// 顶栏与下方气泡区之间的间距。
  static const double bodyTop = 12;

  /// ===== 气泡聊天区 =====

  ///
  /// 气泡区左右留白。
  static const double chatInset = 16;

  ///
  /// 气泡最大宽度（相对可用宽度的比例），留出右侧候选词的呼吸空间。
  static const double bubbleMaxWidthFactor = 0.72;

  ///
  /// 相邻气泡之间的垂直间距。
  static const double bubbleGap = 10;

  ///
  /// 气泡四角圆角；贴近发送方向的一角用更小的 [bubbleTailRadius] 形成「尾巴」。
  static const double bubbleRadius = 12;
  static const double bubbleTailRadius = 4;

  ///
  /// 气泡内部左右留白与上下留白。
  static const double bubblePaddingHorizontal = 12;
  static const double bubblePaddingVertical = 8;

  ///
  /// 气泡文字字号；中文释义与英文单词统一字号，靠颜色区分两侧。
  static const double bubbleTextSize = 14;

  ///
  /// 气泡内词性标签的文字字号（比正文略小、颜色更轻）。
  static const double bubblePosTextSize = 11.5;

  ///
  /// 气泡最低高度；三点动画气泡内容很小时也不至于显得又窄又扁。
  static const double bubbleMinHeight = 36;

  /// ===== 候选词区（文档流，一行两个） =====

  ///
  /// 候选区与上方聊天区之间的间距。
  static const double candidateTop = 12;

  ///
  /// 候选按钮内容的统一内边距。
  ///
  /// 生活化解释：ABCD 徽章距按钮左边、上边、下边的距离必须完全相等
  /// （28 徽章 + 上下 8×2 = 44 按钮高），视觉才对称不歪。
  static const double candidateContentInset = 8;

  ///
  /// 单个候选按钮的固定高度。
  static const double candidateHeight = 44;

  ///
  /// 候选按钮圆角。
  static const double candidateRadius = 10;

  ///
  /// 相邻候选按钮的间距。
  static const double candidateGap = 8;

  ///
  /// 候选按钮文字字号。
  static const double candidateTextSize = 15;

  ///
  /// 候选词左侧 A/B/C/D 序号方块的固定边长。
  static const double optionBadgeSize = 28;

  ///
  /// 序号方块的圆角。
  static const double optionBadgeRadius = 5;

  ///
  /// 序号方块内字母的字号。
  static const double optionBadgeTextSize = 12;

  ///
  /// 序号方块与候选单词之间的水平间距。
  static const double optionBadgeGap = 10;

  /// ===== 「正在输入」三点动画 =====

  ///
  /// 三点动画里每个圆点的直径。
  static const double typingDotSize = 6;

  ///
  /// 相邻圆点之间的间距。
  static const double typingDotGap = 4;

  ///
  /// 三点动画气泡的固定宽度（容纳三个点 + 间距）。
  static const double typingBubbleWidth = 58;

  ///
  /// 假「正在输入」的持续时间。
  ///
  /// 900ms 恰好让三个点从左到右完整点亮一遍再出内容，用户能看清整个过程。
  static const Duration typingDelay = Duration(milliseconds: 900);

  /// ===== 结算页 =====

  ///
  /// 结算页横向留白。
  static const double summaryInset = 24;

  ///
  /// 结算页各大区块之间的垂直间距。
  static const double summarySectionGap = 24;

  ///
  /// 结算页顶部圆形图标底盘的直径与内部图标尺寸。
  static const double summaryAvatarSize = 64;
  static const double summaryAvatarIconSize = 32;

  ///
  /// 结算页标题与副标题字号。
  static const double summaryTitleSize = 20;
  static const double summarySubtitleSize = 14;

  ///
  /// 统计卡之间的间距、标签字号与数值字号。
  static const double summaryStatGap = 12;
  static const double summaryStatLabelSize = 13;
  static const double summaryStatValueSize = 24;

  ///
  /// 结算页底部按钮高度与文字字号。
  static const double summaryButtonHeight = 48;
  static const double summaryButtonTextSize = 16;

  ///
  /// 「需加强」名单标签字号与词条圆角。
  static const double weakChipTextSize = 13;
  static const double weakChipRadius = 8;
}
