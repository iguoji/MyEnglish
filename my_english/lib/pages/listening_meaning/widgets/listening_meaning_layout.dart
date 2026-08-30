///
/// 听音辨义页面的布局尺寸表：集中声明页面用到的间距、圆角等数值常量。
///
/// 顶栏与进度条的数值刻意和随身听保持一致，使两个学习页面切换时不会跳动。
///
abstract final class ListeningMeaningLayout {
  ///
  /// 页面左右的统一留白。
  static const double pageInset = 20;

  ///
  /// 顶栏距离安全区顶部的距离。
  static const double headerTop = 18;

  ///
  /// 返回按钮与右侧占位区共用的固定宽高。
  static const double headerButtonSize = 34;

  ///
  /// 右上角计时文字的字号。
  ///
  /// 四个练习模块（听音辨义、看义选词、拼写巩固、词义连连）的右上角时间
  /// 统一使用这一个数值：以词义连连原来 14 像素为基准 +1，得到 15 像素。
  /// 统一之后，模块之间来回切换时右上角的数字不会再忽大忽小。
  static const double headerTimerTextSize = 15;

  ///
  /// 顶栏与进度条之间的垂直间距。
  static const double progressTop = 10;

  ///
  /// 页面进度条的固定高度。
  static const double progressHeight = 4;

  ///
  /// 中间答题区上下与其他区域之间的留白。
  static const double questionVerticalInset = 20;

  ///
  /// 三个中间子模块在平板或桌面宽屏上的最大宽度。
  static const double questionMaxWidth = 520;

  ///
  /// 单词占位卡与下方纵向 Steps 之间的固定距离。
  static const double questionModuleGap = 14;

  ///
  /// 单词占位卡的固定高度，为加倍后的字母字号提供稳定空间。
  static const double wordCardHeight = 108;

  ///
  /// 单词占位卡内部的左右留白。
  static const double wordCardHorizontalInset = 18;

  ///
  /// 单词中真实空格在占位卡里的可见距离。
  static const double wordSpaceWidth = 12;

  ///
  /// 字母瓷砖（新单词卡）的固定宽度。
  static const double wordTileWidth = 44;

  ///
  /// 字母瓷砖的固定高度。
  static const double wordTileHeight = 56;

  ///
  /// 字母瓷砖的圆角，比卡片更小以突出“格子”质感。
  static const double wordTileRadius = 10;

  ///
  /// 相邻字母瓷砖之间的距离。
  static const double wordTileGap = 6;

  ///
  /// 字母瓷砖中真实单词的字号；新卡片改用更克制的 30 像素。
  static const double wordLetterFontSize = 30;

  ///
  /// 单词卡左上角听音按钮的边长。
  static const double wordCardSpeakerSize = 40;

  ///
  /// 听音按钮与右侧字母瓷砖之间的水平间距。
  static const double wordCardInnerGap = 12;

  ///
  /// 纵向 Steps 左侧圆形节点的固定直径。
  static const double stepMarkerSize = 20;

  ///
  /// 纵向 Steps 节点内 Tabler 图标的固定尺寸。
  static const double stepIconSize = 12;

  ///
  /// 纵向 Steps 节点与右侧内容之间的距离。
  static const double stepContentGap = 12;

  ///
  /// 纵向 Steps 相邻步骤内容之间的垂直距离。
  static const double stepVerticalGap = 16;

  ///
  /// 纵向 Steps 连接线的固定宽度。
  static const double stepConnectorWidth = 2;

  ///
  /// 单个步骤内容的最小高度，短文案也能保持清晰节奏。
  static const double stepContentMinHeight = 52;

  ///
  /// 答案卡四个角的统一圆角。
  static const double cardRadius = 10;

  ///
  /// 中间可滚动区与底部操作区之间的距离。
  static const double bottomSectionTop = 12;

  ///
  /// 底部操作区在 SafeArea 之上继续保留的呼吸空间。
  static const double bottomInset = 20;

  ///
  /// 左侧候选词与右侧操作按钮之间的水平间距。
  static const double columnGap = 12;

  ///
  /// 四个候选词每行的高度。
  ///
  /// 这是**最小**高度：短候选词仍是 48 像素，长候选词换行后按内容自然增高，
  /// 不会因为高度写死而被裁掉半行字。
  static const double optionMinHeight = 48;

  ///
  /// 候选词文字的字号，换行时保持不变（不再为了塞进一行而缩小字号）。
  static const double optionTextSize = 14;

  ///
  /// 候选词多行时的行高倍数。
  ///
  /// 生活化解释：1 表示“行高正好等于字号”，1.18 表示每行留出约 18% 字号的空隙。
  /// 系统默认是 1.2 上下，这里收紧一点点，两行仍放得进原来 48 像素的卡片，
  /// 同时下伸笔画（g、y、p 的尾巴）也不会顶到下一行。
  static const double optionTextLineHeight = 1.18;

  ///
  /// 候选词最多显示三行，再长才用省略号收尾。
  static const int optionMaxLines = 3;

  ///
  /// 候选词文字与卡片右边框之间的留白。
  ///
  /// 左边已经为 A/B/C/D 序号方块让出了完整宽度，右边只需保留和卡片内边距
  /// 一样的呼吸空间，把省下来的宽度全部留给文字，能明显减少换行的次数。
  static const double optionTextRightInset = 10;

  ///
  /// 候选词左侧 A/B/C/D 序号方块的固定边长。
  static const double optionBadgeSize = 28;

  ///
  /// 序号方块与候选按钮左边框之间的距离。
  static const double optionHorizontalInset = 10;

  ///
  /// 相邻候选词行之间的垂直间距。
  static const double optionGap = 10;

  ///
  /// 右侧“提示”和“播放”按钮的高度。
  static const double actionHeight = 48;

  ///
  /// 反馈文字占用的固定高度，防止文案出现时提示模块抖动。
  static const double feedbackHeight = 20;
}
