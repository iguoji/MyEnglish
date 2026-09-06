// 引入设计令牌总表：本表只负责给页面里的元素起业务名字，
// 具体数值一律引用总表的台阶（相当于页面专属 CSS 继承基础 CSS）。
import '../../../common/design/design.dart';
// 引入模块页面模板：顶栏与结算页那两套共用版式已经搬进模板，本表不再重复声明。
import '../../../widgets/module_scaffold.dart';

///
/// 拼写巩固页面的布局尺寸表。
///
/// 把边距、圆角、按键尺寸等“会经常调整的设计数字”集中在一处，
/// 后续改样式不用到多层 Widget 里翻找。
///
/// 数值来源分两类，改动时请勿混淆：
/// 1. 顶栏返回图标、中间数字进度与进度条——刻意复刻听音辨义与词义连连，
///    让三个复习模块切换时顶部完全不跳动，用户感觉是同一套产品；
/// 2. 其余全部——复刻 `ui/拼写巩固.html` 原型，注释中标注了对应的 CSS 值。
///
/// 上面第 1 类现在由模板 `lib/widgets/module_scaffold.dart` 的 [ModuleHeader]
/// 统一提供，本表因此不再有 `headerTop` / `headerButtonSize` / `progressTop`
/// 这一族档位；结算页那一套同理，见 [ModuleSummaryLayout]。
///
/// 「下划线字母格」也不在本表：它已抽成通用组件
/// `lib/widgets/letter_slot.dart`，尺寸由 `LetterSlotLayout` 维护，
/// 拼写巩固与看义选词共用。
///
/// 26 键键盘不在本表：它已抽成通用组件
/// `lib/widgets/qwerty_keyboard.dart`（视觉复刻 ui/听音拼写1.html），
/// 尺寸常量由组件自己维护。
///
/// 「词性及含义」那一整块也不在本表：它已抽成通用组件
/// `lib/widgets/pos_meaning_panel.dart`，原来的 `meaning*` 常量搬进了
/// `PosMeaningPanelLayout`。本表只留下 [meaningSectionTop] /
/// [meaningSectionBottom] 这两个「这块内容摆在页面哪个位置」的留白。
///
/// 本表里**不再有字号**。字号连同字重、文字色一起搬进了主题的文字档位
/// （见 `lib/common/theme.dart`）：页面写 `textTheme.fs1Bold`，一个名字就同时
/// 定下了它多大、多粗、什么颜色——照 Tabler 念，等于 `class="fs-1 fw-bold"`。
/// 原来这里的 12 个 `*TextSize` 常量各自复述一遍同样的字号，改一次字号要改好几处。
/// 字距、留白这类和具体文案绑定的排版参数仍留在本表，例如
/// [playbackLabelLetterSpacing]——胶囊上那几个字刻意拉得比全站更开。
///
abstract final class SpellingLayout {
  ///
  /// 页面左右统一留白（原型 `--app-px: 20px`）。
  ///
  /// 指到模板那一档：顶栏、进度条、正文白卡与键盘共用同一条左右边界。
  static const double pageInset = ModuleScaffoldLayout.pageInset;

  ///
  /// 进度条与下方主体之间的距离（原型 `main` 的 `py-3`）。
  ///
  /// 页面底色统一成首页底色后，这个值同时也是正文白卡四周的上下留白，
  /// 卡片不会贴到进度条或键盘面板上。
  ///
  /// 从 12 改成 20，与听音辨义（`ListeningMeaningLayout.questionVerticalInset`）
  /// 和看义选词（`MeaningWordChoiceLayout.bodyVerticalInset`）取齐。三个模块都是
  /// 「白卡浮在页面底色上、下面接一块操作区」，原型里这一处各写各的，落到真机上
  /// 就变成来回切换模块时白卡上下跳一下。取三方里较宽松的 20：正文白卡本来就该
  /// 离进度条远一点，收紧到 12 反而显得挤。
  static const double bodyVerticalInset = AppSpace.pBase;

  ///
  /// 正文白卡的圆角，直接指向模板表 [ModuleScaffoldLayout.bodyCardRadius]。
  static const double bodyCardRadius = ModuleScaffoldLayout.bodyCardRadius;

  ///
  /// 正文白卡的左右内边距。
  ///
  /// 比听音辨义题目卡的 20 略小：拼写巩固的字母格要按可用宽度排，
  /// 16 像素能少换一行，视觉上仍然留得开。
  static const double bodyCardPaddingHorizontal = AppSpace.p3;

  ///
  /// 正文白卡的上下内边距。
  static const double bodyCardPaddingVertical = AppSpace.p3;

  ///
  /// “词性及含义”标题距离上方拼写区的距离，对应 `听音拼写2.html` 的 `mt-8`。
  static const double meaningSectionTop = AppSpace.p5;

  /// 含义区底部留白，对应原型的 `mb-6`，避免内容贴住键盘面板。
  static const double meaningSectionBottom = AppSpace.pBase;

  /// 播放状态组件距离上方字母格的留白。
  static const double playbackSectionTop = AppSpace.pBase;

  /// 播放状态组件距离下方含义区的留白。
  static const double playbackSectionBottom = AppSpace.p0;

  /// 播放圆形区域的直径，对应 `听音拼写3.html` 的 `h-10 w-10`。
  ///
  /// 指到总表 [AppSize.speakerButton]：听音辨义释义阶段也有一颗同样大的播音圆，
  /// 那一页原先直接引用本表这一档——一个模块的样式挂在另一个模块的表上。
  static const double playbackCircleSize = AppSize.speakerButton;

  /// 播放胶囊的固定总宽度；播放状态切换时外框不会横向变化。
  static const double playbackWidth = 196;

  ///
  /// 胶囊文字区的固定宽度——声纹与状态文字共用同一宽度,保证两行"看起来一样长"。
  ///
  /// 数值来源：把 `playbackWidth` 减去圆按钮（40）、圆按钮内边距（p2+p3）、内容间距
  /// （p3）、右内边距（p3）和一段留白，刚好够放「美式 · 点击播放」这串文案（含 12px
  /// 字号、letterSpacing 1.2）且左右都不顶到胶囊内壁。原值 92 在真机字体下会让尾字
  /// 「放」被 RichText 默认的 `Clip.hardEdge` 硬切掉一点甚至小半，统一加大到 108
  /// 留出 10% 以上的安全余量；切换到更短的「播放中」时也仍然稳稳居中，不会顶到右壁。
  static const double playbackTextWidth = 108;

  /// 播放圆形区域内 Tabler 扬声器图标的字号。
  static const double playbackIconSize = AppIcon.i20;

  /// 胶囊左侧留白，对应原型的 `pl-1.5`。
  static const double playbackCirclePadding = AppSpace.p2;

  /// 胶囊上下留白，对应原型的 `py-1.5`。
  static const double playbackVerticalPadding = AppSpace.p2;

  /// 胶囊右侧留白，对应原型的 `pr-4`。
  static const double playbackTextPaddingRight = AppSpace.p3;

  /// 播放圆形区域与右侧内容的间距，对应原型的 `gap-3`。
  static const double playbackContentGap = AppSpace.p3;

  /// 声纹总高度；比原型音标更克制，避免播放胶囊视觉重心过高。
  static const double waveHeight = 12;

  /// 声纹竖条数量；数量增加后，声纹长度接近下方状态文字。
  static const int waveBarCount = 21;

  /// 声纹竖条宽度，对应原型均衡器的 `w-[2.5px]`。
  static const double waveBarWidth = 2.5;

  /// 播放状态声纹的低频刷新间隔。
  ///
  /// 声纹不承载内容，只是告诉用户“正在播放”。每 100 毫秒换一帧（收敛前是 84），
  /// 视觉上仍然连续，同时避免模拟器以每秒 60 帧持续重绘整页。
  static const int waveTickMs = AppDuration.ms100;

  /// 未播放时静态声纹的高度，保持组件仍有“可播放”提示。
  ///
  /// 这 21 个数是一整条声纹的「侧影」，高低起伏本身就是造型的一部分，
  /// 所以不像间距、字号那样往偶数台阶上归并——把 3、7、9、11 挨个改成
  /// 相邻的偶数，声纹的高低差就被抹平了，看着更像一排整齐的栅栏而不是声波。
  static const List<double> waveIdleHeights = <double>[
    3,
    4,
    6,
    8,
    10,
    8,
    6,
    4,
    6,
    8,
    11,
    9,
    6,
    4,
    7,
    9,
    8,
    6,
    4,
    3,
    3,
  ];

  /// 播放时每根声纹竖条的最低高度。
  ///
  /// 取值刻意等于上面静态侧影里最短的那一根：这样从「没播放」切到「正在播放」
  /// 的那一瞬间，最矮的竖条不会先跳一下再开始起伏。
  static const double waveMinHeight = 3;

  /// 动态声纹在基础高度上允许增加的最大高度。
  static const double waveMaxExtraHeight = 8;

  /// 播放状态文字与声纹之间的间距。
  static const double playbackLabelGap = AppSpace.p1;

  /// 播放状态文字字母间距，对应原型的 `tracking-[0.12em]`。
  static const double playbackLabelLetterSpacing = 1.2;

  // 字母格（下划线 + 光标 + 入场动画）已抽成通用组件
  // `lib/widgets/letter_slot.dart`，原来的 `spellingLetter*` /
  // `spellingUnderline*` / `spellingCaret*` / `letterEntry*` 一族常量
  // 跟着搬进了 `LetterSlotLayout`（值一个没改），看义选词现在共用同一套。

  /// 拼写字母区域与底部提示文字之间的距离。
  static const double spellingStatusTop = AppSpace.p3;

  /// 底部提示文字固定高度，对应 HTML 的 `h-5`。
  static const double spellingStatusHeight = 20;

  /// 答错反馈的抖动时长（原型 `shake .35s`）。
  static const int shakeDurationMs = AppDuration.ms350;

  /// 答错后的红色反馈完整保留时间。
  ///
  /// 生活化解释：错误信息停留 1.2 秒（收敛前是 1 秒），用户看清提示后就能尽快
  /// 重新输入；这一档和看义选词「看清刚填入的单词」用的是同一个值。
  ///
  /// 这段时间键盘保持锁定，避免用户在反馈还没消失时误触下一次输入。
  static const int wrongFeedbackDurationMs = AppDuration.ms1200;

  ///
  /// 答错抖动各关键帧的左右位移（原型 `shake` 的 0/20/40/60/80/100%）。
  ///
  /// 生活化解释：卡片先往左甩 4 像素、再往右 4 像素，来回两次后停回原位，
  /// 像被人捏住摇了摇头说“不对”。
  static const List<double> shakeKeyframes = <double>[0, -4, 4, -4, 4, 0];

  ///
  /// 拼写成功后切到下一个词的停顿时长。
  ///
  /// 与答错提示共用 1 秒：无论答对还是答错，用户都有同样的时间看清反馈，
  /// 不会因为答对了就立刻翻到下一题。
  static const int wordAdvanceDelayMs = wrongFeedbackDurationMs;

  ///
  /// 进入单词后自动发音的延迟（原型 `setTimeout(speakCurrent, 350)`）。
  static const int autoSpeakDelayMs = AppDuration.ms350;

  ///
  /// 结算页那一整块（`summary*` 九档、`weakChip*` 四档）已经搬进模块模板的
  /// [ModuleSummaryLayout]。三个模块练完都会走到同一屏收尾画面，以前靠三张
  /// 页面表各写一份、再靠 `README.md` 里一句「改其中一个，另外两个要一起改」
  /// 维持一致；现在只有一处可改，页面直接写 `ModuleSummaryLayout.inset`。

  ///
  /// 「词性及含义」整块内容的最大宽度。
  ///
  /// 手机上永远够不到这个数，它只在平板或折叠屏展开时起作用：屏幕一宽，含义卡片
  /// 会跟着摊成很长的一行，读完一行找不到下一行。限到 720 之后内容居中成一栏，
  /// 阅读节奏和手机上一致。
  ///
  /// 名字里的 `Panel` 用来和听音辨义的 `meaningTextMaxWidth`（300）区分：那一档
  /// 限的是「一行释义文字」多宽，这一档限的是「整块面板」多宽，只是名字撞了。
  static const double meaningPanelMaxWidth = 720;
}
