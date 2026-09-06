// 引入设计令牌总表：本表只负责给页面里的元素起业务名字，
// 具体数值一律引用总表的台阶（相当于页面专属 CSS 继承基础 CSS）。
import '../../../common/design/design.dart';
// 引入模块页面模板：顶栏与结算页那两套共用版式已经搬进模板，本表不再重复声明。
import '../../../widgets/module_scaffold.dart';

///
/// 词义连连页面的布局尺寸表。
///
/// 把边距、圆角、进度条高度等“会经常调整的设计数字”集中在一处，
/// 后续改样式不用到多层 Widget 里翻找。
///
/// 数值来源分三类，改动时请勿混淆：
/// 1. 顶栏返回图标与中间「已配对 / 总数」——现在整块由模块模板
///    `lib/widgets/module_scaffold.dart` 的 [ModuleHeader] 提供，本表因此不再有
///    `headerTop` / `headerButtonSize` / `progressTop` 这一族档位；
/// 2. 候选词卡片的三种状态（选中 / 连对 / 连错）——复刻
///    `ui/词义连连_部分效果.html` 补充稿里的 `.is-selected / .is-matched / .is-error`；
/// 3. 其余全部——复刻 `ui/词义连连.html` 原型，注释中标注了对应的 CSS 值。
///
/// 结算页那一套（`summary*`）同理，已并入 [ModuleSummaryLayout]。
///
/// 本表里**不再有字号**。字号连同字重、文字色一起搬进了主题的文字档位
/// （见 `lib/common/theme.dart`），页面直接写 `textTheme.fs4Semibold`
/// 这样的档名。原因是字号从来不是「这一页专属」的东西：结算页标题和另外
/// 两个模块的结算页标题必须一样大，以前靠三张表各写一遍 `AppFont.fs1`
/// 来维持，现在三处读同一档，想不一致都难。行高、最大行数这类和具体
/// 文案相关的排版参数仍留在本表。
///
abstract final class MeaningMatchLayout {
  ///
  /// 页面左右统一留白（原型写的是 `--app-px: 20px`，贴 Tabler 档后落到 24）。
  ///
  /// 生活化解释：屏幕左右两边各空出一档页面留白，内容不贴边，看起来更透气。
  /// 指到模板那一档：顶栏、进度条与棋盘共用同一条左右边界。
  static const double pageInset = ModuleScaffoldLayout.pageInset;

  ///
  /// 进度条与下方棋盘之间的距离（原型 `main` 的 `py-3`）。
  static const double boardVerticalInset = AppSpace.p3;

  ///
  /// 倒计时进入“危险色 + 呼吸动画”的阈值秒数（原型 `timeLeft <= 10`）。
  static const int countdownDangerSeconds = 10;

  ///
  /// 倒计时呼吸动画一个来回的时长（原型 `pulseDanger 0.8s infinite`）。
  static const int pulseDurationMs = AppDuration.ms800;

  ///
  /// 呼吸动画放大到的最大倍数（原型 `scale(1.06)`）。
  static const double pulseMaxScale = 1.06;

  ///
  /// 呼吸动画最淡时的不透明度（原型 `opacity: 0.8`）。
  static const double pulseMinOpacity = AppAlpha.a80;

  ///
  /// 相邻候选词卡片之间的纵向距离（原型 `.left-col { gap: 12px }`）。
  static const double sectionGap = AppSpace.p3;

  ///
  /// 左右两列候选词之间的横向间隔（原型 `.matching-grid { gap: 40px }`）。
  static const double boardGap = AppSpace.p6;

  ///
  /// 候选词卡片圆角（原型 `.pair-btn { border-radius: 10px }`）。
  ///
  /// 名字带 `option` 前缀是刻意的：全站有三种「卡」，正文白卡（r8）、候选卡（r10）、
  /// 含义卡（r12），以前三种都叫 `cardRadius`，跨表一比就分不清哪个是哪个，
  /// 注释里还出现过「与听音辨义题目卡一致」却指向候选卡的误记。
  static const double optionCardRadius = AppRadius.roundedLg;

  ///
  /// 候选词卡片最小高度（原型 `min-height: 52px`）。
  static const double cardMinHeight = 52;

  ///
  /// 候选词卡片最大高度（原型 `max-height: 62px`，长释义文本可撑高）。
  static const double cardMaxHeight = 62;

  ///
  /// 候选词卡片左右内边距（原型 `padding: 6px 12px` 的横向部分）。
  static const double optionCardPaddingHorizontal = AppSpace.p3;

  ///
  /// 候选词卡片上下内边距（原型 `padding: 6px 12px` 的纵向部分）。
  static const double optionCardPaddingVertical = AppSpace.p2;

  ///
  /// 候选词文字最多显示的行数（原型 `-webkit-line-clamp: 2`）。
  static const int cardLabelMaxLines = 2;

  ///
  /// 卡片内侧锚点圆点的直径（原型 `.anchor-point { width/height: 8px }`）。
  static const double anchorSize = 8;

  ///
  /// 锚点外圈白边宽度（原型 `border: 1.5px solid #ffffff`），取发丝线档。
  static const double anchorRingWidth = AppStroke.bold;

  ///
  /// 锚点相对卡片内侧边缘外移的距离（原型 `right/left: -4.5px`）。
  ///
  /// 生活化解释：圆点不是画在卡片里面，而是骑在卡片边线上，一半在内一半在外，
  /// 这样连线就能正好从圆点中心出发。
  static const double anchorOverhang = 4.5;

  ///
  /// 匹配成功后绘制的贝塞尔连线宽度（原型 `stroke-width: 2.5`）。
  static const double connectionLineWidth = AppStroke.mark;

  ///
  /// 棋盘正中那条竖直虚线的宽度（原型 `stroke-width="1.5"`）。
  static const double dividerWidth = AppStroke.bold;

  ///
  /// 竖直虚线每一段实线的长度（原型 `stroke-dasharray="8,8"` 的前一个 8）。
  static const double dividerDashLength = 8;

  ///
  /// 竖直虚线每两段之间的空白长度（原型 `stroke-dasharray="8,8"` 的后一个 8）。
  static const double dividerDashGap = AppSpace.p2;

  ///
  /// 卡片状态切换时“变色”的过渡时长（补充稿 `border-color/background-color 0.25s`）。
  ///
  /// 生活化解释：从灰底变蓝底、从蓝底变绿底，都不是一瞬间跳过去，而是用
  /// 四分之一秒慢慢染过去，眼睛才跟得上。
  static const int cardColorTransitionMs = AppDuration.ms250;

  ///
  /// 卡片状态切换时“变形”的过渡时长（补充稿 `transform/box-shadow/opacity 0.35s`）。
  ///
  /// 与连线生长动画同为 350 毫秒，二者同时收尾，连线端点不会脱离锚点。
  static const int cardTransformTransitionMs = AppDuration.ms350;

  ///
  /// 选中卡片的放大倍数（补充稿 `.is-selected { transform: scale(1.02) }`）。
  ///
  /// 生活化解释：被点中的卡片会轻轻“浮起来”一点点，像被手指提了一下。
  static const double selectedScale = 1.02;

  ///
  /// 选中卡片外发光的模糊半径（补充稿 `0 8px 20px -4px` 的 20px 模糊）。
  static const double selectedGlowBlur = 20;

  ///
  /// 选中卡片外发光向内收缩的距离（补充稿 `0 8px 20px -4px` 的 -4px）。
  static const double selectedGlowSpread = -4;

  ///
  /// 选中卡片外发光向下偏移的距离（补充稿 `0 8px 20px -4px` 的 8px）。
  static const double selectedGlowOffsetY = 8;

  ///
  /// 已连上卡片的缩小倍数（补充稿 `.is-matched { transform: scale(0.97) }`）。
  ///
  /// 生活化解释：连对之后卡片会略微“缩水”，配合变淡表示这一对已经消解掉了。
  static const double matchedScale = 0.97;

  ///
  /// 已连上卡片的整体不透明度（补充稿 `.is-matched { opacity: 0.45 }`）。
  ///
  /// 收敛前写 0.45，现在与连错描边、听音辨义步骤条一起读总表同一档。
  static const double matchedOpacity = AppAlpha.a44;

  ///
  /// 选中时锚点圆点的放大倍数（补充稿 `.is-selected .node-anchor { scale(1.3) }`）。
  static const double anchorSelectedScale = 1.3;

  ///
  /// 选中时锚点外圈光晕的宽度（补充稿 `0 0 0 4px rgba(...,0.3)` 减去内圈 2px 白边）。
  static const double anchorSelectedHalo = 2;

  ///
  /// 连错时锚点外圈光晕的宽度（补充稿 `0 0 0 3px rgba(239,68,68,0.25)`）。
  static const double anchorErrorHalo = 3;

  ///
  /// 错误抖动动画时长（补充稿 `animation: errorJolt 0.4s`，0.4 秒并入 350 毫秒）。
  static const int shakeDurationMs = AppDuration.ms350;

  ///
  /// 错误抖动各关键帧的左右位移（补充稿 `errorJolt` 的 0/20/40/60/80/100%）。
  ///
  /// 生活化解释：卡片先猛地往左甩 6 像素，再往右 5 像素，来回幅度一次比一次小，
  /// 最后停回原位，像被人捏住摇了一下头。
  static const List<double> shakeKeyframes = <double>[0, -6, 5, -3, 2, 0];

  ///
  /// 错误抖动最大摆动角度（补充稿 `rotate(±0.5deg)`），单位为度。
  static const double shakeRotationDegrees = 0.5;

  ///
  /// 匹配成功连线绘制动画时长（原型 `drawLine 0.35s`）。
  static const int connectDurationMs = AppDuration.ms350;

  ///
  /// 一组全部匹配后切换到下一组的延迟（原型 `setTimeout(..., 600)`，600 并入 800）。
  static const int groupAdvanceDelayMs = AppDuration.ms800;

  ///
  /// 切换到下一组时整块棋盘的淡入时长（原型 `fadeIn 0.25s`）。
  static const int fadeDurationMs = AppDuration.ms250;

  ///
  /// 淡入时棋盘从下方上移的距离（原型 `translateY(4px)` → `translateY(0)`）。
  static const double fadeSlideOffset = 4;

  ///
  /// 结算页那一整块（`summary*` 九档）已经搬进模块模板的 [ModuleSummaryLayout]。
  /// 三个模块练完都会走到同一屏收尾画面，以前靠三张页面表各写一份、再靠
  /// `README.md` 里一句「改其中一个，另外两个要一起改」维持一致；现在只有
  /// 一处可改，页面直接写 `ModuleSummaryLayout.inset`。
  ///
  /// 有一处原来记在本表里的取舍要跟着搬走：`summaryStatRadius` 与候选卡的
  /// [optionCardRadius] 数值相同、语义不同——一个跟着结算页调，一个跟着配对
  /// 卡片调，所以并表之后它仍然是 [ModuleSummaryLayout.statRadius] 一档，
  /// 没有和候选卡合并。

  ///
  /// 卡片用「投影」描出来的那一圈边，往外扩多宽。
  ///
  /// 生活化解释：这不是真的影子，而是拿一层完全不模糊的同色投影当描边使——
  /// 好处是它画在边框之外，不占卡片内部的宽度，所以描粗一圈也不会把里面的文字
  /// 挤得换行。默认、连对和选中三种状态都用这一圈，只是换个颜色。
  static const double cardBorderSpread = 1;
}
