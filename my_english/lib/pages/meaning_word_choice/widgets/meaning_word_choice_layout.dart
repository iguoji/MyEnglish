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

  /// ===== 右下角候选区 =====

  ///
  /// 候选区与气泡区之间的间距。
  static const double candidateTop = 12;

  ///
  /// 候选区自身留白（左右与底部）。
  static const double candidateInset = 12;

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
  /// 候选区最大宽度；数量多时在范围内自动换行成两列。
  static const double candidateMaxWidth = 176;

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
