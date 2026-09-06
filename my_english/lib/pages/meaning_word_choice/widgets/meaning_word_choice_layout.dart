// 引入设计令牌总表：本表只负责给页面里的元素起业务名字，
// 具体数值一律引用总表的台阶（相当于页面专属 CSS 继承基础 CSS）。
import '../../../common/design/design.dart';
// 引入模块页面模板：顶栏与结算页那两套共用版式已经搬进模板，本表不再重复声明。
import '../../../widgets/module_scaffold.dart';

///
/// 看义选词页面的布局尺寸表：集中声明页面用到的间距、圆角等数值常量。
///
/// 顶栏那一整块（返回键、中间数字进度、右上角用时、进度条）已经交给模块模板
/// `lib/widgets/module_scaffold.dart` 的 [ModuleHeader]，本表里因此不再有
/// `headerTop` / `headerButtonSize` / `progressTop` 这一族档位——它们本来就不是
/// 「这一页专属」的方寸，五个模块必须一模一样。
///
/// 结算页同理：`summary*` 与 `weakChip*` 两族已并入 [ModuleSummaryLayout]，
/// 三个模块的收尾画面从此只有一处可改。
///
/// 正文区对齐听音辨义：一张白卡浮在页面底色上，卡内内容垂直居中，
/// 从上到下是「标签 → 中文释义大字 → 词性说明 → 下划线字母格 → 底部提示」。
/// 字母格自身的尺寸不在本表，它由公共组件 `lib/widgets/letter_slot.dart`
/// 的 `LetterSlotLayout` 维护（与拼写巩固共用同一套）。
///
/// 本表里**不再有字号**：字号连同字重、文字色一起搬进了主题的文字档位
/// （见 `lib/common/theme.dart`），页面直接写 `textTheme.fs4Semibold` 这样的
/// 档名。留在本表里的只有和这一页版式绑定的东西——留白、圆角、最大行数。
///
abstract final class MeaningWordChoiceLayout {
  ///
  /// 页面左右的统一留白。
  ///
  /// 指到模板那一档：顶栏、进度条和正文白卡共用同一条左右边界，分开写迟早会
  /// 出现「进度条比白卡宽几像素」。
  static const double pageInset = ModuleScaffoldLayout.pageInset;

  ///
  /// 顶栏（进度条）与正文白卡之间的间距，同时也是白卡底部留白。
  ///
  /// 取听音辨义 `questionVerticalInset` 的 20：两个模块都是「白卡浮在页面底
  /// 上，下面接候选区」，留白一致，来回切换时白卡不会上下跳。
  static const double bodyVerticalInset = AppSpace.pBase;

  /// ===== 正文白卡 =====

  ///
  /// 白卡圆角，直接指向模板表 [ModuleScaffoldLayout.bodyCardRadius]。
  ///
  /// 名字从 `cardRadius` 改成 `bodyCardRadius`，是为了和候选卡那一档
  /// （`optionCardRadius`，10）彻底分开：两档数值本来就不同，同名只会让人
  /// 误以为它们该一起调。
  static const double bodyCardRadius = ModuleScaffoldLayout.bodyCardRadius;

  ///
  /// 白卡左右内边距。
  static const double bodyCardPaddingHorizontal = AppSpace.pBase;

  ///
  /// 白卡上下内边距。
  static const double bodyCardPaddingVertical = AppSpace.pBase;

  ///
  /// 顶部「选择对应的单词」标签的左右内边距。
  static const double tagPaddingHorizontal = AppSpace.p2;

  ///
  /// 标签上下内边距。
  static const double tagPaddingVertical = AppSpace.p1;

  ///
  /// 标签圆角。
  static const double tagRadius = AppRadius.rounded;

  ///
  /// 标签与下方中文释义大字之间的距离。
  static const double definitionTop = AppSpace.pBase;

  ///
  /// 中文释义最多显示的行数，再长才用省略号收尾。
  static const int definitionMaxLines = 3;

  ///
  /// 释义大字与下方「词性 | 释义」说明行之间的距离。
  static const double posLineTop = AppSpace.p3;

  ///
  /// 说明行与下方字母格之间的距离。
  static const double slotsTop = AppSpace.p5;

  ///
  /// 一条释义对应多个单词时，两组字母格之间的垂直距离。
  static const double slotRowGap = AppSpace.p3;

  ///
  /// 字母格与底部提示文字之间的距离。
  static const double hintTop = AppSpace.pBase;

  ///
  /// 本轮全部答对后，停留多久再切到下一条释义。
  ///
  /// 白卡版必须留这段停顿：答对的瞬间整个单词才刚填进字母格，立刻切题的话
  /// 用户根本看不到自己答出来的词是什么样。
  ///
  /// 取 1200 毫秒：字母填入动画本身要 160 毫秒，剩下一秒左右才够把整个单词
  /// （最长可能十几个字母）看完。原来的 800 毫秒实测偏急——字母刚显现完就
  /// 切题，读起来像「一出现就没了」。
  static const int roundAdvanceDelayMs = AppDuration.ms1200;

  /// ===== 候选词区（文档流，一行两个） =====
  ///
  /// 候选区与上方正文白卡之间的间距**只由白卡底部的 `bodyVerticalInset`
  /// 承担**，候选区自己不再在顶部额外留白：本页没有横幅之类的中间元素插在
  /// 两者之间，若再叠一道顶部留白，两段留白会首尾相接、中间无内容，看起来
  /// 就是“正文和候选词之间空了一大块”。

  ///
  /// 单个候选按钮内容的统一内边距。
  ///
  /// 生活化解释：ABCD 徽章距按钮左边、上边、下边的距离必须完全相等，
  /// 视觉才对称不歪。
  static const double candidateContentInset = AppSpace.p2;

  ///
  /// 单个候选按钮的**最小**高度，也就是「手指可点的下限」。
  ///
  /// 注意它不等于按钮实际显示的高度。按钮的自然高度是自己算出来的：
  /// 28 的 ABCD 徽章 + 上下各 8 的内边距 + 上下各 1 的描边 = 46。
  /// 所以标准字号下看到的按钮是 46 高，这个 44 只是一道底线，
  /// 保证内容再怎么少也不会缩成一条细窄的、手指难点的横杠。
  ///
  /// 之前这里是写死高度，实测的代价是：多出来的 2 像素从徽章身上抠，
  /// 本该 28×28 的正方块被压成 28×26 的扁块；而且字号调到「大 / 特大」
  /// 之后按钮高度不变，放大的单词反被压回原来大小，等于放大失效。
  ///
  /// 44 这个数本身不是本页定的，它是全站「手指可点的下限」，见总表
  /// [AppSize.touchTarget]。
  static const double candidateHeight = AppSize.touchTarget;

  ///
  /// 候选按钮圆角。
  static const double candidateRadius = AppRadius.roundedLg;

  ///
  /// 相邻候选按钮的间距。
  static const double candidateGap = AppSpace.p2;

  ///
  /// 候选词左侧 A/B/C/D 序号方块的固定边长。
  static const double optionBadgeSize = AppSize.optionBadge;

  ///
  /// 序号方块的圆角（与听音辨义的候选序号同一档，收敛前是 5）。
  static const double optionBadgeRadius = AppRadius.rounded;

  ///
  /// 序号方块与候选单词之间的水平间距。
  static const double optionBadgeGap = AppSpace.p2;

  /// ===== 结算页 =====
  ///
  /// 这一族档位（`summary*` 九档、`weakChip*` 四档）已经整块搬进模块模板的
  /// [ModuleSummaryLayout]。原因是它们从来就不是「本页专属」：拼写巩固、
  /// 词义连连、看义选词练完都会走到同一屏收尾画面，以前靠三张页面表各写一份、
  /// 再靠 `README.md` 里一句「改其中一个，另外两个要一起改」维持一致。
  /// 现在只有一处可改，页面直接写 `ModuleSummaryLayout.inset` 这样的名字。
}
