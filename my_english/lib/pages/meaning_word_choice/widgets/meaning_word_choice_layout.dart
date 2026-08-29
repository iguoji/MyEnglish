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
}
