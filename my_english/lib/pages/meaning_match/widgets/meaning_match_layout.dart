///
/// 词义连连页面的布局尺寸表。
///
/// 作用类似于小程序页面共用的 WXSS 变量：把边距、圆角、进度条高度等
/// “会经常调整的设计数字”集中在一处，后续改样式不用到多层 Widget 里翻找。
/// 这里的数值直接复刻听音辨义（ListeningLayout），保证两个复习模块视觉一致。
///
abstract final class MeaningMatchLayout {
  ///
  /// 页面左右统一留白。
  ///
  /// 生活化解释：屏幕左右两边各空出 20 像素，内容不贴边，看起来更透气。
  ///
  /// @var double
  ///
  static const double pageInset = 20;

  ///
  /// 顶栏距离安全区（刘海/状态栏）顶部的距离。
  ///
  /// @var double
  ///
  static const double headerTop = 18;

  ///
  /// 顶栏图标按钮（如返回键）的点击画布大小。
  ///
  /// 生活化解释：这是一个 34×34 的不可见方块，手指点在里面任意位置都能触发按钮。
  ///
  /// @var double
  ///
  static const double headerButtonSize = 34;

  ///
  /// 顶栏与下方进度条之间的纵向间距。
  ///
  /// @var double
  ///
  static const double progressTop = 10;

  ///
  /// 进度条高度。
  ///
  /// @var double
  ///
  static const double progressHeight = 4;

  ///
  /// 相邻卡片之间的纵向距离（候选词区域接入时会用到）。
  ///
  /// @var double
  ///
  static const double sectionGap = 12;

  ///
  /// 页面卡片统一圆角（候选词区域接入时会用到）。
  ///
  /// @var double
  ///
  static const double cardRadius = 10;
}
