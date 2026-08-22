///
/// 词义连连页面的布局尺寸表。
///
/// 作用类似于小程序页面共用的 WXSS 变量：把边距、圆角、进度条高度等
/// “会经常调整的设计数字”集中在一处，后续改样式不用到多层 Widget 里翻找。
///
/// 数值来源分三类，改动时请勿混淆：
/// 1. 顶栏返回图标与中间「已配对 / 总数」——刻意复刻听音辨义（DictationLayout），
///    让两个复习模块切换时顶部完全不跳动，用户感觉是同一套产品；
/// 2. 候选词卡片的三种状态（选中 / 连对 / 连错）——复刻
///    `ui/词义连连_部分效果.html` 补充稿里的 `.is-selected / .is-matched / .is-error`；
/// 3. 其余全部——复刻 `ui/词义连连.html` 原型，注释中标注了对应的 CSS 值。
///
abstract final class MeaningMatchLayout {
  ///
  /// 页面左右统一留白（原型 `--app-px: 20px`，同时也是听音辨义的 pageInset）。
  ///
  /// 生活化解释：屏幕左右两边各空出 20 像素，内容不贴边，看起来更透气。
  ///
  /// @var double
  ///
  static const double pageInset = 20;

  ///
  /// 顶栏距离安全区（刘海/状态栏）顶部的距离。
  ///
  /// 取听音辨义的 18 而不是原型的 16，两个模块顶栏才能严丝合缝对齐。
  ///
  /// @var double
  ///
  static const double headerTop = 18;

  ///
  /// 顶栏图标按钮（返回键）的点击画布大小。
  ///
  /// 生活化解释：这是一个 34×34 的不可见方块，手指点在里面任意位置都能触发按钮。
  ///
  /// @var double
  ///
  static const double headerButtonSize = 34;

  ///
  /// 顶栏返回图标的字号（与听音辨义 `_PlainIconButton` 完全一致）。
  ///
  /// @var double
  ///
  static const double headerIconSize = 21;

  ///
  /// 中间「已配对 / 总数」的字号（与听音辨义题号一致）。
  ///
  /// @var double
  ///
  static const double headerProgressTextSize = 16;

  ///
  /// 顶栏与下方进度条之间的纵向间距（与听音辨义一致）。
  ///
  /// @var double
  ///
  static const double progressTop = 10;

  ///
  /// 时间进度条高度（原型 `height: 3px`）。
  ///
  /// @var double
  ///
  static const double progressHeight = 3;

  ///
  /// 时间进度条圆角（原型 `border-radius: 2px`）。
  ///
  /// @var double
  ///
  static const double progressRadius = 2;

  ///
  /// 进度条与下方棋盘之间的距离（原型 `main` 的 `py-3`）。
  ///
  /// @var double
  ///
  static const double boardVerticalInset = 12;

  ///
  /// 倒计时文本字号（原型 `fs-3` = 1.125rem = 18px）。
  ///
  /// @var double
  ///
  static const double countdownTextSize = 18;

  ///
  /// 倒计时进入“危险色 + 呼吸动画”的阈值秒数（原型 `timeLeft <= 10`）。
  ///
  /// @var int
  ///
  static const int countdownDangerSeconds = 10;

  ///
  /// 倒计时呼吸动画一个来回的时长（原型 `pulseDanger 0.8s infinite`）。
  ///
  /// @var int
  ///
  static const int pulseDurationMs = 800;

  ///
  /// 呼吸动画放大到的最大倍数（原型 `scale(1.06)`）。
  ///
  /// @var double
  ///
  static const double pulseMaxScale = 1.06;

  ///
  /// 呼吸动画最淡时的不透明度（原型 `opacity: 0.8`）。
  ///
  /// @var double
  ///
  static const double pulseMinOpacity = 0.8;

  ///
  /// 相邻候选词卡片之间的纵向距离（原型 `.left-col { gap: 12px }`）。
  ///
  /// @var double
  ///
  static const double sectionGap = 12;

  ///
  /// 左右两列候选词之间的横向间隔（原型 `.matching-grid { gap: 40px }`）。
  ///
  /// @var double
  ///
  static const double boardGap = 40;

  ///
  /// 候选词卡片圆角（原型 `.pair-btn { border-radius: 10px }`）。
  ///
  /// @var double
  ///
  static const double cardRadius = 10;

  ///
  /// 候选词卡片最小高度（原型 `min-height: 52px`）。
  ///
  /// @var double
  ///
  static const double cardMinHeight = 52;

  ///
  /// 候选词卡片最大高度（原型 `max-height: 62px`，长释义文本可撑高）。
  ///
  /// @var double
  ///
  static const double cardMaxHeight = 62;

  ///
  /// 候选词卡片左右内边距（原型 `padding: 6px 12px` 的横向部分）。
  ///
  /// @var double
  ///
  static const double cardPaddingHorizontal = 12;

  ///
  /// 候选词卡片上下内边距（原型 `padding: 6px 12px` 的纵向部分）。
  ///
  /// @var double
  ///
  static const double cardPaddingVertical = 6;

  ///
  /// 候选词文字字号（原型 `.card-label { font-size: 0.8125rem }` = 13px）。
  ///
  /// @var double
  ///
  static const double cardLabelSize = 13;

  ///
  /// 候选词文字行高倍数（原型 `line-height: 1.28`）。
  ///
  /// @var double
  ///
  static const double cardLabelLineHeight = 1.28;

  ///
  /// 候选词文字最多显示的行数（原型 `-webkit-line-clamp: 2`）。
  ///
  /// @var int
  ///
  static const int cardLabelMaxLines = 2;

  ///
  /// 卡片内侧锚点圆点的直径（原型 `.anchor-point { width/height: 8px }`）。
  ///
  /// @var double
  ///
  static const double anchorSize = 8;

  ///
  /// 锚点外圈白边宽度（原型 `border: 1.5px solid #ffffff`）。
  ///
  /// @var double
  ///
  static const double anchorRingWidth = 1.5;

  ///
  /// 锚点相对卡片内侧边缘外移的距离（原型 `right/left: -4.5px`）。
  ///
  /// 生活化解释：圆点不是画在卡片里面，而是骑在卡片边线上，一半在内一半在外，
  /// 这样连线就能正好从圆点中心出发。
  ///
  /// @var double
  ///
  static const double anchorOverhang = 4.5;

  ///
  /// 匹配成功后绘制的贝塞尔连线宽度（原型 `stroke-width: 2.5`）。
  ///
  /// @var double
  ///
  static const double connectionLineWidth = 2.5;

  ///
  /// 棋盘正中那条竖直虚线的宽度（原型 `stroke-width="1.5"`）。
  ///
  /// @var double
  ///
  static const double dividerWidth = 1.5;

  ///
  /// 竖直虚线每一段实线的长度（原型 `stroke-dasharray="8,8"` 的前一个 8）。
  ///
  /// @var double
  ///
  static const double dividerDashLength = 8;

  ///
  /// 竖直虚线每两段之间的空白长度（原型 `stroke-dasharray="8,8"` 的后一个 8）。
  ///
  /// @var double
  ///
  static const double dividerDashGap = 8;

  ///
  /// 卡片状态切换时“变色”的过渡时长（补充稿 `border-color/background-color 0.25s`）。
  ///
  /// 生活化解释：从灰底变蓝底、从蓝底变绿底，都不是一瞬间跳过去，而是用
  /// 四分之一秒慢慢染过去，眼睛才跟得上。
  ///
  /// @var int
  ///
  static const int cardColorTransitionMs = 250;

  ///
  /// 卡片状态切换时“变形”的过渡时长（补充稿 `transform/box-shadow/opacity 0.35s`）。
  ///
  /// 与连线生长动画同为 350 毫秒，二者同时收尾，连线端点不会脱离锚点。
  ///
  /// @var int
  ///
  static const int cardTransformTransitionMs = 350;

  ///
  /// 选中卡片的放大倍数（补充稿 `.is-selected { transform: scale(1.02) }`）。
  ///
  /// 生活化解释：被点中的卡片会轻轻“浮起来”一点点，像被手指提了一下。
  ///
  /// @var double
  ///
  static const double selectedScale = 1.02;

  ///
  /// 选中卡片外发光的模糊半径（补充稿 `0 8px 20px -4px` 的 20px 模糊）。
  ///
  /// @var double
  ///
  static const double selectedGlowBlur = 20;

  ///
  /// 选中卡片外发光向内收缩的距离（补充稿 `0 8px 20px -4px` 的 -4px）。
  ///
  /// @var double
  ///
  static const double selectedGlowSpread = -4;

  ///
  /// 选中卡片外发光向下偏移的距离（补充稿 `0 8px 20px -4px` 的 8px）。
  ///
  /// @var double
  ///
  static const double selectedGlowOffsetY = 8;

  ///
  /// 已连上卡片的缩小倍数（补充稿 `.is-matched { transform: scale(0.97) }`）。
  ///
  /// 生活化解释：连对之后卡片会略微“缩水”，配合变淡表示这一对已经消解掉了。
  ///
  /// @var double
  ///
  static const double matchedScale = 0.97;

  ///
  /// 已连上卡片的整体不透明度（补充稿 `.is-matched { opacity: 0.45 }`）。
  ///
  /// @var double
  ///
  static const double matchedOpacity = 0.45;

  ///
  /// 选中时锚点圆点的放大倍数（补充稿 `.is-selected .node-anchor { scale(1.3) }`）。
  ///
  /// @var double
  ///
  static const double anchorSelectedScale = 1.3;

  ///
  /// 选中时锚点外圈光晕的宽度（补充稿 `0 0 0 4px rgba(...,0.3)` 减去内圈 2px 白边）。
  ///
  /// @var double
  ///
  static const double anchorSelectedHalo = 2;

  ///
  /// 连错时锚点外圈光晕的宽度（补充稿 `0 0 0 3px rgba(239,68,68,0.25)`）。
  ///
  /// @var double
  ///
  static const double anchorErrorHalo = 3;

  ///
  /// 错误抖动动画时长（补充稿 `animation: errorJolt 0.4s`）。
  ///
  /// @var int
  ///
  static const int shakeDurationMs = 400;

  ///
  /// 错误抖动各关键帧的左右位移（补充稿 `errorJolt` 的 0/20/40/60/80/100%）。
  ///
  /// 生活化解释：卡片先猛地往左甩 6 像素，再往右 5 像素，来回幅度一次比一次小，
  /// 最后停回原位，像被人捏住摇了一下头。
  ///
  /// @var `List<double>`
  ///
  static const List<double> shakeKeyframes = <double>[0, -6, 5, -3, 2, 0];

  ///
  /// 错误抖动最大摆动角度（补充稿 `rotate(±0.5deg)`），单位为度。
  ///
  /// @var double
  ///
  static const double shakeRotationDegrees = 0.5;

  ///
  /// 匹配成功连线绘制动画时长（原型 `drawLine 0.35s`）。
  ///
  /// @var int
  ///
  static const int connectDurationMs = 350;

  ///
  /// 一组全部匹配后切换到下一组的延迟（原型 `setTimeout(..., 600)`）。
  ///
  /// @var int
  ///
  static const int groupAdvanceDelayMs = 600;

  ///
  /// 切换到下一组时整块棋盘的淡入时长（原型 `fadeIn 0.25s`）。
  ///
  /// @var int
  ///
  static const int fadeDurationMs = 250;

  ///
  /// 淡入时棋盘从下方上移的距离（原型 `translateY(4px)` → `translateY(0)`）。
  ///
  /// @var double
  ///
  static const double fadeSlideOffset = 4;

  ///
  /// 结算页左右留白（原型 `padding-left/right: 50px`）。
  ///
  /// @var double
  ///
  static const double summaryInset = 50;

  ///
  /// 结算页三大块（头部、统计、按钮）之间的间距（原型 `gap-4` = 1.5rem）。
  ///
  /// @var double
  ///
  static const double summarySectionGap = 24;

  ///
  /// 结算页顶部圆形图标底盘直径（原型 `avatar avatar-xl` = 4rem）。
  ///
  /// @var double
  ///
  static const double summaryAvatarSize = 64;

  ///
  /// 结算页圆形底盘内的 Tabler 图标字号（原型 `fs-1` = 1.5rem）。
  ///
  /// @var double
  ///
  static const double summaryAvatarIconSize = 24;

  ///
  /// 结算页主标题字号（原型 `fs-1` = 1.5rem）。
  ///
  /// @var double
  ///
  static const double summaryTitleSize = 24;

  ///
  /// 结算页副标题字号（原型 `small`）。
  ///
  /// @var double
  ///
  static const double summarySubtitleSize = 12;

  ///
  /// 结算页 2×2 统计卡之间的间距（原型 `row g-2` = 0.5rem）。
  ///
  /// @var double
  ///
  static const double summaryStatGap = 8;

  ///
  /// 结算页统计卡上下内边距（原型 `py-3` = 1rem）。
  ///
  /// @var double
  ///
  static const double summaryStatPaddingVertical = 16;

  ///
  /// 结算页统计卡标题字号（原型 `small`）。
  ///
  /// @var double
  ///
  static const double summaryStatLabelSize = 12;

  ///
  /// 结算页统计卡主数值字号（原型 `display-6`）。
  ///
  /// @var double
  ///
  static const double summaryStatValueSize = 40;

  ///
  /// 结算页“剩余时间”这一格的数值字号（原型 `fs-1`，因为 00:00 比纯数字长）。
  ///
  /// @var double
  ///
  static const double summaryStatTimeSize = 24;

  ///
  /// 结算页统计卡底部单位说明字号（原型 `text-xs`）。
  ///
  /// @var double
  ///
  static const double summaryStatUnitSize = 10;

  ///
  /// 结算页底部“再挑战一次”按钮高度（原型 `btn py-2 fs-3` 的实际渲染高度）。
  ///
  /// @var double
  ///
  static const double summaryButtonHeight = 46;
}
