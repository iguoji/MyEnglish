// material.dart 提供模板需要的 Scaffold、SafeArea、Column 与线性进度条。
import 'package:flutter/material.dart';
// services.dart 提供 SystemUiOverlayStyle：下段自带底色时要把系统导航区一起染色。
import 'package:flutter/services.dart';
// 所有可见图标继续统一使用 Tabler。

// 引入设计令牌总表：本文件的尺寸表只负责起业务名字，数值一律引用总表的台阶。
import '../common/theme.dart';

///
/// 学习模块页面的**模板**：把五个模块页「长得一样的那一层」收成一处。
///
/// 五个模块页（随身听、听音辨义、词义连连、看义选词、拼写巩固）从上到下都是
/// 同一副骨架：
///
/// ```text
/// 上：顶栏（返回键 + 中间「第几个 / 总数」+ 右上角时间）+ 一条进度条 ← 五个模块相同
/// 中：正文                                                     ← 每个模块自己填
/// 下：操作区（候选词、键盘、播放控制……）                          ← 自己填，也可以没有
/// ```
///
/// 以前这副骨架在五个页面里各抄了一遍：五份顶栏 `Stack`、五份 34×34 返回键、
/// 四份右上角时间、五份进度条。抄得再仔细也会走偏，真机上就表现为切换模块时
/// 顶部跳一下。现在骨架只有这一份，模块只负责往「中」和「下」两个口子里填东西。
///
/// 填法就是 Laravel Blade 的插槽（slot）：模板留好位置，使用者把自己的组件塞进
/// 对应的具名参数。对照关系是
///
/// ```text
/// @yield('header') → ModuleScaffold.header（不传就是默认顶栏 ModuleHeader）
/// @yield('body')   → ModuleScaffold.body
/// @yield('footer') → ModuleScaffold.footer
/// ```
///
/// 顶栏自己也是一个带三个插槽的小模板（[ModuleHeader]）：左 `leading`、中 `title`、
/// 右 `trailing`，不传就用默认件（左边是返回键，右边空着）。所以新开一个模块，
/// 最少只要写「中」这一个插槽。
///
/// 练完那一屏（结算页）同样是模板：三个模块的收尾画面从上到下也是同一副骨架，
/// 见 [ModuleSummaryView]，里面的统计卡是 [ModuleSummaryStatCard]。
///
/// 顶栏用到的那几档尺寸放在 [ModuleScaffoldLayout]，结算页共用的那一套版式放在
/// [ModuleSummaryLayout]——都在本文件里，改模板时只看这一处。
///
abstract final class ModuleScaffoldLayout {
  ///
  /// 页面左右的统一留白。
  ///
  /// 顶栏、进度条和正文共用同一条左右边界，所以五张页面尺寸表里的 `pageInset`
  /// 都指到这一档：改一次，顶栏和正文一起动，不会出现「进度条比正文宽 4 像素」。
  static const double pageInset = AppSpace.pBase;

  ///
  /// 顶栏距离安全区（刘海 / 状态栏）顶部的距离。
  static const double headerTop = AppSpace.p3;

  ///
  /// 顶栏行高，同时也是返回键的点击画布边长。
  ///
  /// 这是一行写死的高度，字号放大后里面的数字会跟着变高，所以
  /// `test/font_scale_pressure_test.dart` 会在每一档字号下量一次余量。
  static const double headerButtonSize = AppSize.headerRow;

  ///
  /// 顶栏图标的尺寸（返回键、随身听的设置键）。
  static const double headerIconSize = AppIcon.i20;

  ///
  /// 正文白卡的圆角。
  ///
  /// 「白卡浮在页面底色上」是四个模块共同的正文骨架，所以圆角也是共同的一档：
  /// 收进这里之前，听音辨义、拼写巩固、看义选词三张页面尺寸表各写了一遍同一个
  /// 值，改一处另外两处不会跟着变，切换模块时白卡的转角就会一个圆一个方。
  static const double bodyCardRadius = AppRadius.roundedLg;

  ///
  /// 顶栏与下方进度条之间的纵向间距。
  static const double progressTop = AppSpace.p2;

  ///
  /// 进度条的固定高度。
  static const double progressHeight = AppSize.progressBar;

  ///
  /// 进度条两端的圆角。
  static const double progressRadius = AppRadius.roundedSm;
}

///
/// 三个复习模块**结算页**共用的版式表。
///
/// 拼写巩固、看义选词、词义连连练完都会走到同一屏收尾画面：顶部一个圆形庆祝
/// 图标、中间 2×2 四张统计卡、底部一颗大按钮。留白、圆角、按钮高度如果各写一遍，
/// 用户来回切换会觉得「这是三个不同的 App」。
///
/// 以前靠三张页面尺寸表各写一份、再靠 `README.md` 里一句「改其中一个，另外两个
/// 要一起改」维持一致。现在收成这一张表：想不一致都难，因为只有一处可改。
///
/// 末尾四档 `weakChip*`（「需加强」词条）只有拼写巩固和看义选词有，词义连连的
/// 结算页没有这一块，所以那四档是**两方**共用，不是三方。它们现在只被公共组件
/// [ModuleSummaryWeakList] 读，页面里不再直接出现。
///
abstract final class ModuleSummaryLayout {
  ///
  /// 结算页左右留白。
  ///
  /// 比答题屏的 20 宽得多：结算页只有几行字和一颗按钮，留白给足才显得是
  /// 「收尾页」而不是「又一道题」。
  static const double inset = AppSpace.p6;

  ///
  /// 顶部圆形图标底盘的直径。
  static const double avatarSize = AppSize.summaryAvatar;

  ///
  /// 圆形底盘里那个图标的尺寸。
  ///
  /// 与听音辨义完成页同款（直径 64 的圆里放一枚 32 的图标），四个模块的
  /// 结算页才能长成同一种收尾。
  static const double avatarIconSize = AppIcon.i32;

  ///
  /// 图标与标题、标题与说明行之间的纵向间距。
  static const double textGap = AppSpace.p3;

  ///
  /// 说明行与底部按钮之间的纵向间距。
  static const double actionTop = AppSpace.pBase;

  ///
  /// 底部主按钮的最小宽度（胶囊按钮，文案「返回」时约 100 宽）。
  ///
  /// 用最小宽度而不是写死宽度：以后按钮文案换长一点，胶囊能自己变宽。
  static const double buttonMinWidth = 112;

  ///
  /// 底部主按钮的高度。
  static const double buttonHeight = 40;
}

///
/// 五个模块页共用的**页面骨架**：上、中、下三段。
///
/// 用法（拼写巩固答题屏为例，下段是那块铺满宽度的灰蓝键盘）：
///
/// ```dart
/// ModuleScaffold(
///   header: ModuleHeader(title: ..., progress: ...),
///   body: _buildGame(tokens),
///   footer: _buildKeyboard(),
///   footerColor: QwertyKeyboard.panelColor(context),
///   footerBorderColor: AppTokens.keyPanelBorder,
/// )
/// ```
///
class ModuleScaffold extends StatelessWidget {
  ///
  /// 只有「中」这一段是必填的，其余插槽都能省。
  const ModuleScaffold({
    required this.header,
    required this.body,
    this.footer,
    this.footerColor,
    this.footerBorderColor,
    this.systemUiOverlayStyle,
    this.canPop = true,
    super.key,
  });

  ///
  /// 上段：顶栏。通常直接塞一个 [ModuleHeader]。
  final Widget header;

  ///
  /// 中段：正文。它会自动吃掉上下两段之外的全部高度。
  final Widget body;

  ///
  /// 下段：操作区。不传表示这个模块没有底部操作区（词义连连就没有）。
  final Widget? footer;

  ///
  /// 下段自己的背景色。
  ///
  /// 不传（null）时，下段和正文一样躺在页面底色上、待在安全区里面——随身听的播放
  /// 控制条、听音辨义的候选词都是这一种。
  ///
  /// 传了颜色时，下段会**一直铺到屏幕最底边**，连系统手势导航区那一条也染成同色，
  /// 键盘和屏幕底边之间不会露出一条白缝。拼写巩固的 26 键键盘走的是这一路。
  final Color? footerColor;

  ///
  /// 下段顶部那条分隔线的颜色；只在 [footerColor] 有值时才画。
  final Color? footerBorderColor;

  ///
  /// 需要连系统状态栏、导航栏一起换色时传入。
  final SystemUiOverlayStyle? systemUiOverlayStyle;

  ///
  /// 是否允许系统返回手势退出本页。
  ///
  /// 传 false 会把返回手势拦住，用在「成绩正在写库」这类中途退出就丢数据的时刻。
  final bool canPop;

  ///
  /// 把三个插槽拼成一页。
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // 下段自带底色时要一直铺到屏幕最底边，因此安全区必须拆成上下两段分别处理。
    final paintsOwnFooter = footerColor != null;

    // 上、中、下三段：中间那段吃掉剩余高度，上下两段各占自身实际高度。
    final sections = Column(
      children: [
        header,
        Expanded(child: body),
        if (footer != null && !paintsOwnFooter) footer!,
      ],
    );

    final Widget content;
    if (paintsOwnFooter) {
      content = Column(
        children: [
          // 上、中两段自己避开刘海，底边留给下面那块自带底色的区域。
          Expanded(child: SafeArea(bottom: false, child: sections)),
          // 底色和上边框画在 SafeArea 外层，才能连系统手势区的那段内边距一起
          // 染成同色；画在里层就会在键盘下方露出一条白缝。
          Container(
            decoration: BoxDecoration(
              color: footerColor,
              border: footerBorderColor == null
                  ? null
                  : Border(top: BorderSide(color: footerBorderColor!)),
            ),
            child: SafeArea(
              top: false,
              left: false,
              right: false,
              // 下段始终占满屏幕宽度，内部留白由具体组件自己处理。
              child: SizedBox(width: double.infinity, child: footer),
            ),
          ),
        ],
      );
    } else {
      content = SafeArea(child: sections);
    }

    // 六个页面共用 AppTokens.page 这一个底色，切模块时背景不跳。
    final Widget page = Scaffold(backgroundColor: tokens.page, body: content);

    // PopScope 一直挂着而不是「需要时才套一层」：树的形状保持不变，
    // canPop 翻转时正文里的动画和输入状态才不会被连根重建。
    final Widget guarded = PopScope<Object?>(canPop: canPop, child: page);

    if (systemUiOverlayStyle == null) {
      return guarded;
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemUiOverlayStyle!,
      child: guarded,
    );
  }
}

///
/// 顶栏模板：一行三个插槽，下面挂一条进度条。
///
/// ```text
/// ┌──────────────────────────────────────┐
/// │ leading        title        trailing │  ← 34 像素高的一行
/// ├──────────────────────────────────────┤
/// │ ████████████░░░░░░░░░░░░░░░░░░░░░░░░ │  ← progress，不传就不画
/// └──────────────────────────────────────┘
/// ```
///
/// 三个插槽用**绝对定位**而不是左中右排队：左边返回键 34 像素、右边时间约 50 像素，
/// 宽度并不相等，排队摆放会把中间那个数字挤得偏左几像素，只有绝对定位能让它
/// 严格居中。
///
class ModuleHeader extends StatelessWidget {
  ///
  /// 中间那一份是必填的，其余插槽都有默认件或可以省。
  const ModuleHeader({
    required this.title,
    this.leading,
    this.trailing,
    this.progress,
    this.progressColor,
    this.progressBarKey,
    super.key,
  });

  ///
  /// 中间插槽：通常是 [ModuleProgressLabel]（「第几个 / 总数」）。
  final Widget title;

  ///
  /// 左侧插槽。不传就是默认返回键：Tabler 左箭头，点一下退出本页。
  final Widget? leading;

  ///
  /// 右侧插槽：四个复习模块放 [ModuleTimeLabel]，随身听放设置键，可以不传。
  final Widget? trailing;

  ///
  /// 进度条的完成比例，取 0～1。不传表示这个模块顶栏没有进度条。
  final double? progress;

  ///
  /// 进度条已完成那一段的颜色，默认品牌蓝。
  ///
  /// 词义连连在最后 10 秒把它整条换成危险红，和倒计时文字同步告警。
  final Color? progressColor;

  ///
  /// 进度条的 Key，交给页面自己命名（Widget 测试要按 Key 找到它量高度）。
  final Key? progressBarKey;

  ///
  /// 拼出顶栏那一行和它下面的进度条。
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Column(
      // 顶栏只占自身实际高度，不抢中段正文的空间。
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ModuleScaffoldLayout.pageInset,
            ModuleScaffoldLayout.headerTop,
            ModuleScaffoldLayout.pageInset,
            AppSpace.p0,
          ),
          child: SizedBox(
            height: ModuleScaffoldLayout.headerButtonSize,
            child: Stack(
              children: [
                // 中间那一份先铺满整行再自我居中，两侧插槽压在它上面。
                Positioned.fill(child: Center(child: title)),
                Align(
                  alignment: Alignment.centerLeft,
                  child:
                      leading ??
                      ModuleIconButton(
                        icon: AppGlyph.back,
                        alignment: Alignment.centerLeft,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                ),
                if (trailing != null)
                  Align(alignment: Alignment.centerRight, child: trailing!),
              ],
            ),
          ),
        ),
        // 进度条的左右边界与顶栏严格对齐，读的是同一档 pageInset。
        if (progress != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ModuleScaffoldLayout.pageInset,
              ModuleScaffoldLayout.progressTop,
              ModuleScaffoldLayout.pageInset,
              AppSpace.p0,
            ),
            // ClipRRect 只负责把进度条两端裁成轻微圆角。
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                ModuleScaffoldLayout.progressRadius,
              ),
              child: LinearProgressIndicator(
                key: progressBarKey,
                value: progress,
                minHeight: ModuleScaffoldLayout.progressHeight,
                backgroundColor: tokens.sub,
                color: progressColor ?? AppTokens.primary,
              ),
            ),
          ),
      ],
    );
  }
}

///
/// 固定画布的无背景图标按钮：整个 App 只此一份。
///
/// 收敛前它在五个地方各写了一遍（听音辨义、看义选词各一个私有 `_PlainIconButton`，
/// 随身听一个公开的 `ListeningIconButton`，词义连连和拼写巩固直接把
/// `SizedBox + InkWell + Align + Icon` 内联在顶栏里）。五份实现做的是同一件事，
/// 改一处必然漏另外四处。
///
/// 两个设计约定要留着：
/// 1. 点击画布固定 34×34，不依赖图标自身的透明边距——换图标不用重算任何偏移；
/// 2. 图标靠 [alignment] 在画布内对齐，**不允许用负数偏移**把它顶出画布。
///    左侧返回键用 `centerLeft`，这样图标本体正好贴在页面左右留白那条线上
///    （[ModuleScaffoldLayout.pageInset]）。
///
class ModuleIconButton extends StatelessWidget {
  ///
  /// 只接收图标、点击回调、画布内对齐方式和可选颜色。
  const ModuleIconButton({
    required this.icon,
    required this.onTap,
    this.alignment = Alignment.center,
    this.color,
    super.key,
  });

  ///
  /// 要显示的 Tabler 图标。
  final IconData icon;

  ///
  /// 点击后执行的业务回调。
  final VoidCallback onTap;

  ///
  /// 图标在 34 像素画布里的对齐方式。
  final AlignmentGeometry alignment;

  ///
  /// 图标颜色，不传时用主题里的次要文字色。
  final Color? color;

  ///
  /// 画出画布、水波纹和图标。
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // SizedBox 明确声明完整点击画布，不让图标自身的透明空间影响顶栏对齐。
    return SizedBox(
      width: ModuleScaffoldLayout.headerButtonSize,
      height: ModuleScaffoldLayout.headerButtonSize,
      // InkWell 负责点击命中与圆形按压反馈。
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
          ModuleScaffoldLayout.headerButtonSize / 2,
        ),
        // Align 用正常布局约束对齐图标，不需要任何负数偏移。
        child: Align(
          alignment: alignment,
          child: Icon(
            icon,
            size: ModuleScaffoldLayout.headerIconSize,
            color: color ?? tokens.textMedium,
          ),
        ),
      ),
    );
  }
}

///
/// 顶栏中间的「第几个 / 总数」。
///
/// 五个模块的这一行必须一模一样：同一档文字、同一种等宽数字、同一个斜杠格式。
/// 以前格式串在五个页面里各拼一遍，`'$a / $b'` 少写一个空格就会看出差别。
///
class ModuleProgressLabel extends StatelessWidget {
  ///
  /// 传入当前序号与总数，格式化交给本组件。
  const ModuleProgressLabel({
    required this.current,
    required this.total,
    this.textKey,
    super.key,
  });

  ///
  /// 当前是第几个（从 1 开始，不是下标）。
  final int current;

  ///
  /// 一共多少个。
  final int total;

  ///
  /// 挂在**文字本体**上的 Key，由页面自己命名。
  ///
  /// 为什么不直接用组件自己的 `key`：Widget 测试里有 `tester.widget<Text>(...)`
  /// 这样按类型取控件的写法，Key 挂在外层组件上时找到的是本组件而不是 `Text`，
  /// 取不到文字内容。挂到里层，页面和测试看到的都还是那一行字。
  final Key? textKey;

  ///
  /// 排出居中的一行进度数字。
  @override
  Widget build(BuildContext context) {
    return Text(
      '$current / $total',
      key: textKey,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.fs4Semibold.copyWith(
        // 等宽数字让每个数字占同样宽度，计数变化时视觉中心不抖动。
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

///
/// 顶栏右上角的时间。
///
/// 四个复习模块都用这一份：看义选词、听音辨义、拼写巩固显示本局已用时间，
/// 词义连连显示剩余时间。字号与中间的主进度相同但**不加粗**——时间是次要信息，
/// 不该和主进度抢视觉权重。
///
class ModuleTimeLabel extends StatelessWidget {
  ///
  /// 时间文本由页面格式化好后传进来（mm:ss 或 hh:mm:ss）。
  const ModuleTimeLabel({
    required this.text,
    this.color,
    this.textKey,
    super.key,
  });

  ///
  /// 已经排好版的时间文本。
  final String text;

  ///
  /// 文字颜色，不传时用主题里的次要文字色。
  ///
  /// 只有词义连连会传：它的倒计时会随剩余时间从灰转橙转红。默认那一档取的正是
  /// 这里的次要文字色，所以四个模块的「正常状态」颜色本来就是同一个。
  final Color? color;

  ///
  /// 挂在**文字本体**上的 Key，理由同 [ModuleProgressLabel.textKey]。
  final Key? textKey;

  ///
  /// 排出一行等宽数字的时间。
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Text(
      text,
      key: textKey,
      style: Theme.of(context).textTheme.fs4.copyWith(
        color: color ?? tokens.textMedium,
        // 等宽数字让秒数变化时整体宽度稳定，右侧不抖动。
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

///
/// 结算页模板：练完那一屏的上中下三段。
///
/// 拼写巩固、看义选词、词义连连练完都会走到这一屏，从上到下永远是同一副骨架：
///
/// ```text
/// 上：圆形庆祝图标 + 主标题 + 副标题          ← 三个模块相同，只有图标和文案不同
/// 中：2×2 四张统计卡（+ 可选的「需加强」名单）  ← 卡片内容自己填
/// 下：一颗「再来一次」大按钮                   ← 只有文案和回调不同
/// ```
///
/// 收敛前这副骨架在三个页面里各抄了一遍，一共约 450 行几乎逐字相同的代码：
/// 三份 `LayoutBuilder + SingleChildScrollView + ConstrainedBox`、三份圆形图标
/// 底盘、三份 2×2 矩阵、三份底部按钮。抄的时候还各自走偏了一点点——同一张统计卡
/// 在词义连连有左右内边距、另两个没有，字号行距也差着一档。
///
/// 现在骨架只有这一份，页面只填内容。可换的地方仍然是 Blade 式的插槽：
/// [footnote] 就是留给「需加强」名单的那个口子，词义连连不传就不占位置。
///
class ModuleSummaryView extends StatelessWidget {
  ///
  /// 创建一个极简结算页。
  const ModuleSummaryView({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    this.actionKey,
    super.key,
  });

  ///
  /// 顶部圆形底盘里的图标。
  ///
  /// 四个模块统一后都传「对勾」，超时结算（词义连连）也可以传时钟等失败语义图标。
  final IconData icon;

  ///
  /// 这一屏的主色：底盘淡色背景和图标都取它。
  ///
  /// 四个模块的取法不同——拼写巩固、看义选词恒定用成功绿，词义连连赢了用绿、
  /// 超时用红——所以它是页面传进来的，不是模板写死的。
  final Color color;

  ///
  /// 主标题，如「拼写完成」「听音辨义完成」「大获全胜！」。
  final String title;

  ///
  /// 说明行：一句话交代本组成绩，如「共 10 个单词 · 答错 2 次」。
  final String subtitle;

  ///
  /// 底部按钮文案，四个模块统一为「返回」。
  final String actionLabel;

  ///
  /// 底部按钮的点击回调，通常是页面的「退出并回上一页」。
  final VoidCallback onAction;

  ///
  /// 底部按钮的 Key，交给页面自己命名（Widget 测试要按 Key 点它）。
  final Key? actionKey;

  ///
  /// 把内容填进极简结算骨架。
  ///
  /// 版式与听音辨义完成页完全一致（那是全站第一个做成这种样式的收尾屏）：
  /// 圆形图标底盘 → 主标题 → 一行说明 → 胶囊按钮，整体垂直居中。原先的
  /// 2×2 统计卡方阵与「需加强」名单已按「结算页统一走简单显示」下线，
  /// 等结算页整体重构时再决定要不要以新形式回来。
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        // 只限制左右留白；内容高度不足一屏时，Center 让它停在剩余空间的中心。
        padding: const EdgeInsets.symmetric(
          horizontal: ModuleSummaryLayout.inset,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 圆形图标底盘：直径 64，底色是主色的 10% 淡版。
            Container(
              width: ModuleSummaryLayout.avatarSize,
              height: ModuleSummaryLayout.avatarSize,
              decoration: BoxDecoration(
                color: color.withValues(alpha: AppAlpha.a10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: ModuleSummaryLayout.avatarIconSize,
                color: color,
              ),
            ),
            const SizedBox(height: ModuleSummaryLayout.textGap),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.fs3Semibold,
            ),
            const SizedBox(height: ModuleSummaryLayout.textGap),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: textTheme.fs5.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: ModuleSummaryLayout.actionTop),
            // 胶囊形主按钮：四个模块的收尾都是这一颗「返回」。
            FilledButton(
              key: actionKey,
              onPressed: onAction,
              style: FilledButton.styleFrom(
                minimumSize: const Size(
                  ModuleSummaryLayout.buttonMinWidth,
                  ModuleSummaryLayout.buttonHeight,
                ),
                shape: const StadiumBorder(),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
///
/// 结算页的 2×2 统计卡（ModuleSummaryStatCard）与「需加强」名单
/// （ModuleSummaryWeakEntry / ModuleSummaryWeakList / _ModuleSummaryWeakChip）
/// 已随「结算页统一走简单显示」一起下线：四个模块的收尾屏都改成听音辨义
/// 完成页那一种（图标 + 标题 + 一行说明 + 返回按钮），统计与错词名单
/// 不再单独展示。结算页整体重构时若需要以新形式回归，可从 git 历史找回。
