// 引入设计令牌总表：本表只负责给页面里的元素起业务名字，
// 具体数值一律引用总表的台阶（相当于页面专属 CSS 继承基础 CSS）。
import '../../../common/design/design.dart';
// 引入模块页面模板：顶栏那一套共用版式已经搬进模板，本表不再重复声明。
import '../../../widgets/module_scaffold.dart';

///
/// 听音辨义页面的布局尺寸表：集中声明页面用到的间距、圆角等数值常量。
///
/// 顶栏那一整块（返回键、中间题号、右上角用时、进度条）已经交给模块模板
/// `lib/widgets/module_scaffold.dart` 的 [ModuleHeader]，本表因此不再有
/// `headerTop` / `headerButtonSize` / `progressTop` / `progressHeight` 这一族
/// 档位——它们本来就不是「这一页专属」的方寸，五个模块必须一模一样。
///
/// 本表里只剩两个字号，而且都不是「直接拿来写样式」的：[optionTextSize] 要参与
/// 「一行放不下就缩 2 像素」的计算，必须是个能做减法的数字；[wordLetterFontSize]
/// 是旧版单词卡留下的，目前只有测试还在引用。其余字号连同字重、文字色一起搬进了
/// 主题的文字档位（见 `lib/common/theme.dart`），页面写 `textTheme.fs3Semibold`
/// 就同时定下了它多大、多粗、什么颜色——名字照 Tabler 念，等于 CSS 里的
/// `class="fs-3 fw-semibold"`。
///
abstract final class ListeningMeaningLayout {
  ///
  /// 页面左右的统一留白。
  ///
  /// 指到模板那一档：顶栏、进度条与正文白卡共用同一条左右边界。
  static const double pageInset = ModuleScaffoldLayout.pageInset;

  ///
  /// 中间答题区上下与其他区域之间的留白。
  static const double questionVerticalInset = AppSpace.pBase;

  ///
  /// 三个中间子模块在平板或桌面宽屏上的最大宽度。
  static const double questionMaxWidth = 520;

  // 「单词占位卡」那一族档位（`questionModuleGap`、`wordCardHeight`、
  // `wordCardHorizontalInset`、`wordSpaceWidth`、`wordTile*` 四档、
  // `wordCardSpeakerSize`、`wordCardInnerGap`）已经整块删除。
  //
  // 生活化解释：这一版界面早就不画那张「一个字母一个格子」的占位卡了，题目区
  // 现在是一张白卡加一颗大播音圆。但那 10 个尺寸还留在表里，谁读这张表都会以为
  // 页面上有一排字母瓷砖，改半天发现改不动任何东西。
  //
  // 判断依据不是猜的：全仓（含测试）搜 `ListeningMeaningLayout.wordTileWidth`
  // 这类名字，一处引用都没有。

  ///
  /// 早期单词占位卡里那个大号字母的字号。
  ///
  /// **这一档已经没有界面在用**，只有 `listening_meaning_page_test.dart` 还量它。
  /// 保留是为了不动测试；等那条断言一起清理时，本档也可以删掉。
  static const double wordLetterFontSize = AppFont.fs1;

  ///
  /// 出题阶段那个大圆听音按钮的直径。
  ///
  /// 88 是从 HTML 原型的 `.speaker` 直接量下来的：这一屏只有这一个可点的东西，
  /// 圆做大是想让人一眼知道「先点我听」。它是一个造型尺寸而不是图标尺寸，
  /// 所以不去凑 12/14/16/20/24/32 那套图标台阶，单独在这里记一笔。
  static const double questionSpeakerSize = 88;

  // 「纵向 Steps」那一族档位（`wordCardInnerGap`、`stepMarkerSize`、
  // `stepIconSize`、`stepContentGap`、`stepVerticalGap`、`stepConnectorWidth`、
  // `stepContentMinHeight`）同样整块删除，理由和上面那族一样：
  //
  // 生活化解释：早期这一页左边有一条竖着的步骤条——一串小圆点用细线连起来，
  // 圆点里画勾表示这一步做完了。现在改成了题目卡顶部一条横的进度段，竖步骤条
  // 连一行代码都不剩，只剩这 7 个尺寸在表里占位置。
  //
  // 顺带一提，`stepIconSize` 是总表 `AppIcon.i12` 唯一的使用者，它一走，
  // 12 这一档图标尺寸也就没人用了，`icons.dart` 里那一档跟着删掉。

  ///
  /// 题目白卡四个角的圆角。
  ///
  /// 全站三种「卡」各有一档、彼此不同，别混用：正文白卡 8、候选卡 10
  /// （[optionCardRadius]）、词性含义卡 12（`PosMeaningPanelLayout.meaningCardRadius`）。
  /// 这一档以前没有名字，直接在题目卡那一行写 `AppRadius.roundedLg`，结果拼写巩固和
  /// 看义选词的注释都说自己「与听音辨义题目卡一致」，却没有一个常量能对得上。
  ///
  /// 现在数值指向模板表 [ModuleScaffoldLayout.bodyCardRadius]：三个模块的正文
  /// 白卡是同一块骨架，圆角也就只有那一处可改。
  static const double bodyCardRadius = ModuleScaffoldLayout.bodyCardRadius;

  ///
  /// 候选答案卡与答题反馈条的统一圆角。
  ///
  /// 和词义连连的候选卡（`MeaningMatchLayout.optionCardRadius`）同一档：两个模块
  /// 的候选卡挨着切换，圆角不一样会立刻看出是两套东西。它**不是**题目白卡的圆角，
  /// 那一档在 [bodyCardRadius]。
  static const double optionCardRadius = AppRadius.roundedLg;

  ///
  /// 底部操作区在 SafeArea 之上继续保留的呼吸空间。
  static const double bottomActionInset = AppSpace.pBase;

  ///
  /// 左侧候选词与右侧操作按钮之间的水平间距。
  static const double columnGap = AppSpace.p3;

  ///
  /// 四个候选词每行的高度。
  ///
  /// 这是**最小**高度：短候选词仍是 48 像素，长候选词换行后按内容自然增高，
  /// 不会因为高度写死而被裁掉半行字。
  static const double optionMinHeight = 48;

  ///
  /// 候选词文字的基准字号：一行放得下时用它。
  static const double optionTextSize = AppFont.fs5;

  ///
  /// 候选词需要换行时把字号缩小的像素数。
  ///
  /// 只缩 2 像素（14 → 12）：既能让两行更紧凑、卡片不至于太高，
  /// 又不像整体等比缩小那样缩到看不清。
  static const double optionTextShrinkStep = 2;

  ///
  /// 候选词最多显示三行，再长才用省略号收尾。
  static const int optionMaxLines = 3;

  ///
  /// 候选词文字与卡片右边框之间的留白。
  ///
  /// 左边已经为 A/B/C/D 序号方块让出了完整宽度，右边只需保留和卡片内边距
  /// 一样的呼吸空间，把省下来的宽度全部留给文字，能明显减少换行的次数。
  static const double optionTextRightInset = AppSpace.p2;

  ///
  /// 候选词左侧 A/B/C/D 序号方块的固定边长。
  static const double optionBadgeSize = AppSize.optionBadge;

  ///
  /// 序号方块与候选按钮左边框之间的距离。
  static const double optionHorizontalInset = AppSpace.p2;

  ///
  /// 相邻候选词行之间的垂直间距。
  static const double optionGap = AppSpace.p2;

  ///
  /// 右侧“提示”和“播放”按钮的高度。
  static const double actionHeight = 48;

  ///
  /// 释义阶段那个大号单词的行高倍数。
  ///
  /// 压到 1.1 表示行盒只比字号高一成。这一行用的是全站最大那一档字号，
  /// 按默认行距会在单词上下各留出一大片空白，把播音胶囊推得太远。
  ///
  /// **它是全站唯一还留在页面尺寸表里的行高**，其余十四档都已并进总表的
  /// `AppLine`（[AppLine.lh1] 1 / [AppLine.lhSm] 1.2 / [AppLine.lhSm] 1.3 /
  /// [AppLine.lhBase] 1.43 / [AppLine.lhBase] 1.5）。这一档没有并进去，是因为
  /// 上下两档都不能用：往下取 1 会把 g、y、p 的尾巴直接切掉（40 像素的字号下
  /// 一眼就看得见），往上取 1.2 又会把播音胶囊再推远几个像素，正好是这一档
  /// 当初压紧想解决的问题。全站只有这一处用最大字号排单行大字，所以它留在本表。
  static const double wordLineHeight = 1.1;

  // 「大号单词的字距 -0.76」这一档已经删除。40 像素的字号下收紧 0.76，等于每个
  // 字母之间少了不到 2% 的空隙，谁也看不出来；真正决定长单词换不换行的是字号和
  // 屏幕宽度，不是这不到一个像素的调整。

  // 「释义文字限宽 300」这一档（`meaningTextMaxWidth`）已经删除。以前词性及
  // 含义面板被这道限宽卡成 300 的窄条、又被正文区居中，面板到白卡左右边缘
  // 会各空出远超 pBase 的距离；去掉限宽让面板横向铺满内容区后，卡边到面板
  // 正好是正文的 pBase 内边距。若以后需要给释义限宽，应在排版组件里直接约束
  // 文字而不是约束整块面板，避免再出现「内容窄 + 居中 = 大边距」的问题。

  // 完成页（doneBadgeSize / doneButtonMinWidth / doneButtonHeight）三个常量已随
  // 完成屏收进公共结算组件 ModuleSummaryView 的 ModuleSummaryLayout：四个模块的
  // 收尾屏统一后，直径 64 的圆、112 宽 40 高的胶囊按钮都只此一处维护。
}
