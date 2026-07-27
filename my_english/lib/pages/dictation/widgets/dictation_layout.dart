/// 默写页面的布局尺寸表，作用类似小程序 WXSS 中集中声明的尺寸变量。
///
/// 顶栏与进度条的数值刻意和随身听保持一致，使两个学习页面切换时不会跳动。
abstract final class DictationLayout {
  /// 页面左右的统一留白。
  static const double pageInset = 20;

  /// 顶栏距离安全区顶部的距离。
  static const double headerTop = 18;

  /// 返回按钮与右侧占位区共用的固定宽高。
  static const double headerButtonSize = 34;

  /// 顶栏与进度条之间的垂直间距。
  static const double progressTop = 10;

  /// 页面进度条的固定高度。
  static const double progressHeight = 4;

  /// 中间答题区上下与其他区域之间的留白。
  static const double questionVerticalInset = 20;

  /// 三个中间子模块在平板或桌面宽屏上的最大宽度。
  static const double questionMaxWidth = 520;

  /// 单词占位卡与下方纵向 Steps 之间的固定距离。
  static const double questionModuleGap = 14;

  /// 单词占位卡的固定高度，为加倍后的字母字号提供稳定空间。
  static const double wordCardHeight = 108;

  /// 单词占位卡内部的左右留白。
  static const double wordCardHorizontalInset = 18;

  /// 每一个英文字母占位槽的设计宽度。
  static const double letterSlotWidth = 40;

  /// 每一个英文字母占位槽的固定高度。
  static const double letterSlotHeight = 60;

  /// 相邻字母占位槽之间的距离。
  static const double letterSlotGap = 5;

  /// 单词中真实空格在占位卡里的可见距离。
  static const double wordSpaceWidth = 12;

  /// 字母槽中真实单词的字号；原 22 像素按本轮需求准确放大一倍。
  static const double wordLetterFontSize = 44;

  /// 纵向 Steps 左侧圆形节点的固定直径。
  static const double stepMarkerSize = 20;

  /// 纵向 Steps 节点与右侧内容之间的距离。
  static const double stepContentGap = 12;

  /// 纵向 Steps 相邻步骤内容之间的垂直距离。
  static const double stepVerticalGap = 16;

  /// 纵向 Steps 连接线的固定宽度。
  static const double stepConnectorWidth = 2;

  /// 单个步骤内容的最小高度，短文案也能保持清晰节奏。
  static const double stepContentMinHeight = 52;

  /// 答案卡四个角的统一圆角。
  static const double cardRadius = 10;

  /// 中间可滚动区与底部操作区之间的距离。
  static const double bottomSectionTop = 12;

  /// 底部操作区在 SafeArea 之上继续保留的呼吸空间。
  static const double bottomInset = 20;

  /// 左侧候选词与右侧操作按钮之间的水平间距。
  static const double columnGap = 12;

  /// 四个候选词每行的固定高度。
  static const double optionHeight = 48;

  /// 候选词左侧 A/B/C/D 序号方块的固定边长。
  static const double optionBadgeSize = 28;

  /// 序号方块与候选按钮左边框之间的距离。
  static const double optionHorizontalInset = 10;

  /// 相邻候选词行之间的垂直间距。
  static const double optionGap = 10;

  /// 四个候选词加上三段间距后的总高度，右侧两个按钮以此作为上下对齐边界。
  static const double optionStackHeight = optionHeight * 4 + optionGap * 3;

  /// 右侧“提示”和“播放”按钮的高度。
  static const double actionHeight = 48;

  /// 左侧候选词所占的 flex 份数，三份对一份即约 75% 宽度。
  static const int optionColumnFlex = 3;

  /// 右侧提示与播放所占的 flex 份数。
  static const int actionColumnFlex = 1;

  /// 反馈文字占用的固定高度，防止文案出现时提示模块抖动。
  static const double feedbackHeight = 20;
}
