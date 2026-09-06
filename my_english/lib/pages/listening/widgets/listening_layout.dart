// 引入设计令牌总表：本表只负责给页面里的元素起业务名字，
// 具体数值一律引用总表的台阶（相当于页面专属 CSS 继承基础 CSS）。
import '../../../common/design/design.dart';
// 引入模块页面模板：顶栏那一套共用版式已经搬进模板，本表不再重复声明。
import '../../../widgets/module_scaffold.dart';

///
/// 随身听页面的布局尺寸表：集中声明页面用到的间距、圆角等数值常量。
///
/// 所有边距和控件尺寸集中在这里，后续调整设计时不需要到多层 Widget 中寻找散落数字。
///
/// 顶栏那一整块（返回键、中间「第几个 / 总数」、右上角设置键、进度条）已经交给
/// 模块模板 `lib/widgets/module_scaffold.dart` 的 [ModuleHeader]，本表因此不再有
/// `headerTop` / `headerButtonSize` / `progressTop` / `progressHeight` 这一族档位。
/// 随身听是这套顶栏的原版，四个复习模块当初是照它抄的；抄件与原件从此读同一份代码。
///
abstract final class ListeningLayout {
  ///
  /// 页面左右统一留白。
  ///
  /// 指到模板那一档：顶栏、进度条、播放列表与答案卡共用同一条左右边界。
  static const double pageInset = ModuleScaffoldLayout.pageInset;

  ///
  /// 相邻卡片之间的纵向距离。
  static const double sectionGap = AppSpace.p3;

  ///
  /// 上方播放列表卡片的固定高度。
  static const double playlistHeight = 180;

  ///
  /// 播放列表工具栏四周留白。
  static const double playlistToolbarInset = AppSpace.p2;

  ///
  /// 搜索框与上下跳转按钮共享的高度和按钮宽度。
  static const double compactControlSize = 32;

  ///
  /// 播放列表中每个单词行的固定高度。
  static const double playlistRowHeight = 32;

  ///
  /// 页面卡片统一圆角。
  static const double cardRadius = AppRadius.roundedLg;

  ///
  /// 答案卡正文距离卡片边缘的基础留白。
  static const double answerContentInset = AppSpace.p3;

  ///
  /// 眼睛按钮距离答案卡顶部和右侧的合法正数边距。
  static const double answerActionInset = AppSpace.p2;

  ///
  /// 正文右侧额外预留空间，避免文字进入眼睛按钮的点击区域。
  ///
  /// 中间那一项是眼睛按钮的画布边长，读的是模板顶栏那一档：这颗按钮和顶栏返回键
  /// 用的是同一个 [ModuleIconButton]，画布跟着模板改，本表就不能自己再记一份。
  static const double answerContentRightInset =
      answerActionInset +
      ModuleScaffoldLayout.headerButtonSize +
      answerContentInset;

  ///
  /// 设置面板每一项的固定行高。
  ///
  /// 指到总表 [AppSize.settingsRow]：首页抽屉里的普通设置行是同一种东西——
  /// 左边一句说明、右边一个开关或数字，两处行高必须一致。
  static const double settingsRowHeight = AppSize.settingsRow;

  ///
  /// 单词骨架在字符宽度之外增加的基础宽度。
  static const double spellingSkeletonBaseWidth = 40;

  ///
  /// 单词骨架为每个字母估算的宽度。
  static const double spellingSkeletonCharacterWidth = 12;

  ///
  /// 单词骨架最大宽度，避免极长拼写挤占整行。
  static const double spellingSkeletonMaxWidth = 260;

  ///
  /// 释义骨架在字符宽度之外增加的基础宽度。
  static const double definitionSkeletonBaseWidth = 20;

  ///
  /// 释义骨架为每个中文字符估算的宽度。
  static const double definitionSkeletonCharacterWidth = 14;

  ///
  /// 释义骨架最大宽度。
  static const double definitionSkeletonMaxWidth = 300;

  ///
  /// 播放列表与上方搜索工具栏之间那条分隔线所占的高度。
  ///
  /// 注意这里是 Material `Divider` 的 `height`，指**整条分隔线控件占多高**，
  /// 不是线本身多粗。给成一根线的粗细（[AppStroke.thin]）就等于说
  /// 「除了那条线本身，上下不要留任何空隙」，工具栏和列表才能紧贴。
  static const double playlistDividerHeight = AppStroke.thin;

  // 「播放列表里单词的字距 0.5」这一档已经删除。它当初想解决的是「遮住的字母数
  // 不好数」，可列表里的遮罩本来就是一串圆点（`•`），圆点自带左右留白，本来就是
  // 一颗一颗分开的，再加半个像素看不出任何区别。

  ///
  /// 底部那颗大圆播放 / 暂停按钮的直径。
  static const double playButtonSize = 54;

  ///
  /// 那颗大圆按钮的投影高度。
  ///
  /// 「投影高度」是 Material 的说法：数字越大，投影越散越远，看着离页面越高。
  /// 这里刻意留在 7 这个奇数上——它是从原型直接量下来的，改成 8 全站没有第二处
  /// 会跟着一起变，只会让这颗按钮的影子悄悄挪一下位置。
  static const double playButtonElevation = 7;

  ///
  /// 设置项里数字步进器中间那块数值区的宽度。
  ///
  /// 写死宽度是为了让数值从 5 变成 100 时，两侧的加减按钮不会左右移动。
  ///
  /// 它和总表里「手指可点的下限」（[AppSize.touchTarget]）都是 44，但只是数字撞了：
  /// 那一档说的是「可点的东西不该更矮」，这里说的是「一块文字要占多宽」。
  /// 真并成一档，以后想把可点下限调大，这块数值区会莫名跟着变宽。
  static const double stepperValueWidth = 44;

  ///
  /// 步进器加减按钮的点击方块边长。
  ///
  /// 同样和总表里的候选项序号方块（[AppSize.optionBadge]）撞了 28 这个数字，
  /// 但那是听音辨义候选卡左侧的 A/B/C/D 方块，与本页这两颗小按钮毫无关系。
  static const double stepButtonSize = 28;
}
