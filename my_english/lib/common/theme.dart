// material.dart 提供 ColorScheme 和 ThemeData，用于定义应用的全局样式。
import 'package:flutter/material.dart';

// 设计令牌总表：颜色、字号、间距、圆角、造型尺寸、图标、时长七张表。
import 'design/design.dart';

// 整份转发出去，这样页面只 import 本文件就能同时拿到 AppTheme 与全部令牌，
// 56 个文件里现有的 `import '../../common/theme.dart'` 一行都不用改。
export 'design/design.dart';

///
/// 应用级主题配置；页面从 Theme.of(context) 取颜色，才能同时适配 Light 与 Dark。
///
/// 颜色一律来自 [AppTokens]：这里只负责把令牌接进 Material 的 ColorScheme 与
/// 各组件主题，不再自己声明色值。想改配色请改 `design/colors.dart`。
///
abstract final class AppTheme {
  ///
  /// 全局浅色主题；所有页面都继承同一套 Material 3 行为和颜色。
  static final ThemeData light = _build(AppTokens.light, Brightness.light);

  ///
  /// 全局深色主题；组件尺寸与浅色相同，只替换语义颜色。
  static final ThemeData dark = _build(AppTokens.dark, Brightness.dark);

  ///
  /// 按一组令牌织出完整主题。
  ///
  /// 明暗两套只有取值不同，行为必须完全一致，所以合成一个函数——以前是复制粘贴
  /// 的两大段，改一处忘另一处的情况发生过不止一次。
  static ThemeData _build(AppTokens tokens, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      // 正式启用 Material 3；旧代码关闭它只是为了暂时规避默认尺寸变化。
      useMaterial3: true,
      // 让 Android 边缘手势返回支持「预测返回」（predictive back）：
      // 手指从左边缘右滑时，当前页面会跟着手指实时滑动后退，与左上角返回按钮
      // 的观感一致。若不配置，Flutter 默认转场在手势越过阈值时会直接瞬间 pop，
      // 在真机上表现为「划一下突然消失」不跟手。
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
      // seedColor 让 Material 3 自动派生按钮等语义颜色，再用 copyWith 固定
      // 项目真正在用的那几个 Tabler 中性色。
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: AppTokens.primary,
            brightness: brightness,
          ).copyWith(
            // 深色背景上的蓝色稍微提亮以保持对比度。
            primary: isDark ? AppTokens.primaryBright : AppTokens.primary,
            // surface 是列表、输入框和底部面板的底色。
            surface: tokens.card,
            // onSurface 是 surface 上的主文字。
            onSurface: tokens.text,
            // onSurfaceVariant 用于日期、placeholder 等次要信息。
            onSurfaceVariant: tokens.textSecondary,
            // outline 用于输入框等普通边框。
            outline: tokens.inputBorder,
            // outlineVariant 用于表格这类更轻的分隔线。
            outlineVariant: tokens.border,
            // 深色背景下使用更亮的红色保证可读性。
            error: isDark ? AppTokens.dangerBright : AppTokens.danger,
          ),
      // 页面外围使用略灰背景，内容列表仍使用白色 surface。
      scaffoldBackgroundColor: tokens.page,
      // Divider 和自定义列表边线统一读取此颜色。
      dividerColor: tokens.border,
      // 全局关闭所有交互控件的按下背景与涟漪：暗色模式下 InkWell / IconButton
      // 默认的高亮背景非常刺眼（亮色主题下浅灰不易察觉，所以之前没发现）。
      // 在主题层统一关掉，即可覆盖全站按钮——包括首页汉堡菜单、各页面返回按钮、
      // FAB、列表行、抽屉项等所有使用 InkWell 或 IconButton 的地方。
      splashFactory: NoSplash.splashFactory,
      // 涟漪颜色、长按高亮、悬停底色全部设为透明，杜绝任何可见的按下反馈色块。
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      // 图标按钮（如首页右上角汉堡菜单、删除含义的 IconButton）按下时的高亮
      // 覆盖层同样设为透明，并复用无涟漪工厂。
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          overlayColor: WidgetStatePropertyAll<Color>(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      // 纯文字 TextButton 只改变文字本身，不在按下时出现灰色或蓝色背景块。
      textButtonTheme: const TextButtonThemeData(
        style: ButtonStyle(
          // pressed、hovered、focused 等状态都保持透明覆盖层。
          overlayColor: WidgetStatePropertyAll<Color>(Colors.transparent),
          // 同时关闭水波纹，避免透明覆盖层之外仍出现扩散动画。
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      // 实心主按钮（「下一题」「刷新」「再练一组」「返回」）的统一造型。
      //
      // 收进主题之前，这四颗按钮各自写了一遍「蓝底、白字、圆角 8」——一模一样的
      // 三行抄了四份。就像 CSS 里给 `.btn-primary` 写一次类，而不是在每个按钮的
      // style 属性里各写一遍颜色。
      //
      // 蓝色刻意取不随明暗变化的 [AppTokens.primary]，而不是 Material 会在深色下
      // 自动提亮的 primary：页面里的品牌蓝全站同一个值，深浅两套主题不跑偏。
      // 确实需要例外的按钮（如听音辨义完成页那颗胶囊形「返回」）在自己那一行
      // 覆盖 `shape` 即可，写法和 CSS 的就近覆盖一样。
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppTokens.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          ),
        ),
      ),
      // 描边次要按钮（「取消」「再试一次」）的统一造型：卡片底色 + 中等强调
      // 文字 + 输入框那一档边框，视觉权重刻意低于旁边的实心主按钮。
      //
      // 同样是收口：原来两处各写一遍这三行，改一次配色要记得改两处。
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: tokens.card,
          foregroundColor: tokens.textMedium,
          side: BorderSide(color: tokens.inputBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
          ),
        ),
      ),
      // 轻提示 SnackBar：浅色界面用深底浅字，深色界面用比 surface 略亮的深底。
      // 必须显式覆盖——Material 3 默认的 inverseSurface 在深色色板下偏白，
      // 不改的话任何 SnackBar 在暗色模式都会变成刺眼的白条。
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? tokens.border : tokens.text,
        contentTextStyle: TextStyle(
          color: isDark ? tokens.text : Colors.white,
          fontSize: AppFont.fs5,
        ),
        // 操作按钮（若有）使用品牌蓝。
        actionTextColor: isDark ? AppTokens.primaryBright : AppTokens.primary,
      ),
      // Tooltip 同样指定深色底浅字，规避 Material 3 默认在深色 scheme 下的浅白底。
      tooltipTheme: TooltipThemeData(
        // 圆角气泡，深色底。
        decoration: BoxDecoration(
          color: isDark ? tokens.border : tokens.text,
          borderRadius: BorderRadius.circular(AppRadius.rounded),
        ),
        // 气泡内文字使用小字号。
        textStyle: TextStyle(
          color: isDark ? tokens.text : Colors.white,
          fontSize: AppFont.fs6,
        ),
      ),
      // 不指定 fontFamily，让 Android 根据中英文自动选择系统字体。
      // 但字号与字重必须指定：Material 3 自带的一套 Typography 从 11 到 57
      // 全是它自己的数值，不接管的话「没写 style 的那些文字」会绕过本项目
      // 的字号表，老年版放大时它们的比例也就跟别人不一样了。
      textTheme: _textTheme(tokens),
      scrollbarTheme: ScrollbarThemeData(
        // 桌面和移动端始终使用清晰但不过黑的灰蓝滑块；深色下稍亮一点，
        // 保证真机上容易找到并拖动。
        thumbColor: WidgetStatePropertyAll<Color>(tokens.scrollThumb),
        // 4 像素便于拖动，同时不会遮住日期。
        thickness: const WidgetStatePropertyAll<double>(AppSpace.p1),
        // 仅做轻微圆角。
        radius: const Radius.circular(AppRadius.roundedSm),
      ),
    );
  }

  ///
  /// 把 [AppFont] 的六个字号台阶接到 Material 的 15 个文字槽位上。
  ///
  /// Material 把文字分成 display / headline / title / body / label 五族，
  /// 每族三档（Large / Medium / Small）。这里做的是一次「翻译」：
  /// 它的槽位名 → 本项目的台阶。翻译表只有一份，页面写 `textTheme.fs5`
  /// 拿到的就一定是 `AppFont.fs5`，不会是 Material 自己那套 14.0 / 0.25
  /// 字距的默认值。
  ///
  /// 槽位名本身不好读（`bodyMedium` 只说「正文族中号」，不说到底多大），
  /// 所以本文件末尾还有一层 [TablerTextTheme]，把这 15 个槽位换成 Tabler
  /// 的说法（`fs5`、`fs5Semibold`）。页面只跟那一层打交道，这张翻译表是
  /// 给它撑底的，不必在页面里直接念槽位名。
  ///
  /// 为什么值得做这件事：
  ///
  ///   1. **兜住「没写 style 的文字」。** 项目里绝大多数文字都自带 `TextStyle`，
  ///      但 Flutter 内置组件（对话框标题、SnackBar、下拉菜单项）用的是主题里的
  ///      槽位。不接管的话这些地方会一直用 Material 的原生字号，和全站不一致。
  ///   2. **给「老年版」一个统一的放大对象。** 放大是在 App 最外层拧一个倍数，
  ///      作用于所有文字；前提是所有文字的原始字号都出自同一张表。
  ///   3. **为后续替换内联样式铺路。** 以后逐页把内联 `TextStyle(fontSize: ...)`
  ///      换成读这张表，页面代码会短很多，也不必再各写一遍颜色。
  ///
  /// 颜色统一给到 [AppTokens.text]：明暗两套各织一次，所以深色主题下拿到的是
  /// 深色的正文色，不需要页面自己判断。
  ///
  /// 行距一并钉死（[AppLine]）。这一项容易被忽略却很关键：Material 会给每个槽位
  /// 垫一套**自己的**拉丁排版参数，不写就等于默认接受「行高 1.12 到 1.5 各不
  /// 相同」。那套数字不在任何一张令牌表里，页面上一行字的行高凭什么是 1.29
  /// 谁也说不清。写明之后，15 个槽位的行距全部来自 [AppLine] 这一处。
  ///
  /// 字距**不写**：Material 那套字距（大标题 -0.25、正文 0.25、小标签 0.5）
  /// 全是不到半个像素的微调，屏幕上分辨不出来，写进来只会让人以为这里有讲究。
  /// 唯一一处真需要拉开字距的地方（拼写巩固的播放状态标签）在它自己的页面尺寸
  /// 表里单独设置。
  static TextTheme _textTheme(AppTokens tokens) {
    // 同一族里只有字号和字重不同，所以用一个小工厂收口，避免写 15 遍颜色与行距。
    TextStyle style(double size, FontWeight weight) => TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: tokens.text,
      height: AppLine.lhBase,
    );

    return TextTheme(
      // display 族：全站最大的三档，只出现在结算页的大数字与大字题干上。
      displayLarge: style(AppFont.display6, AppWeight.bold),
      displayMedium: style(AppFont.fs1, AppWeight.bold),
      displaySmall: style(AppFont.fs1, AppWeight.bold),
      // headline 族：页面级标题（结算页主标题、首页问候语）。
      headlineLarge: style(AppFont.fs1, AppWeight.bold),
      headlineMedium: style(AppFont.fs3, AppWeight.bold),
      headlineSmall: style(AppFont.fs3, AppWeight.semibold),
      // title 族：区块小标题与顶栏数字，比正文粗半档。
      titleLarge: style(AppFont.fs4, AppWeight.semibold),
      titleMedium: style(AppFont.fs5, AppWeight.semibold),
      titleSmall: style(AppFont.fs6, AppWeight.semibold),
      // body 族：正文。bodyMedium 是 Flutter 的默认文字样式，
      // 所以它必须正好等于本项目的正文档（[AppFont.fs5]）。
      bodyLarge: style(AppFont.fs4, AppWeight.normal),
      bodyMedium: style(AppFont.fs5, AppWeight.normal),
      bodySmall: style(AppFont.fs6, AppWeight.normal),
      // label 族：按钮文字、标签、单位与角标。
      labelLarge: style(AppFont.fs5, AppWeight.semibold),
      labelMedium: style(AppFont.fs6, AppWeight.semibold),
      labelSmall: style(AppFont.fs6, AppWeight.semibold),
    );
  }
}

///
/// 给 Material 的文字槽位挂一层 Tabler 名字，页面里就不用再念 `bodyMedium`、
/// `titleSmall` 这类名字了。
///
/// **为什么要多这一层。** 槽位名是 Flutter 框架自己的 API，改不掉；而它那套
/// 命名只交代「哪一族的第几档」，不交代多大多粗——`bodyMedium` 里的 medium
/// 到底是 14 号还是 16 号，光看名字答不出来，得回头翻 [AppTheme] 里那张翻译
/// 表。Tabler 的说法则是直说的：14 号常规就写 `class="fs-5"`，14 号半粗就写
/// `class="fs-5 fw-semibold"`。这一层就是把后面那种写法搬成 Dart 的名字，
/// 和全站其他样式变量（`AppSpace.pBase`、`AppFont.fs5`）保持同一种口音。
///
/// **怎么读。** 规则和 CSS 完全一样：
///
///   - `fs5`         ← `.fs-5`                → 14 号常规
///   - `fs5Semibold` ← `.fs-5 .fw-semibold`   → 14 号半粗
///   - 没有字重后缀就是常规（`.fw-normal`）。这和 CSS 里「不写 `fw-*` 就是
///     常规」一个道理，也正是本项目「能继承的就不单独设置」那条约定。
///
/// **和字号表 [AppFont] 的分工。** `AppFont.fs5` 是那一档的**数字**（14），
/// `textTheme.fs5` 是那一档配好颜色、行距、字重之后的**整套文字样式**。
/// 两处的 `fs5` 永远指同一档，不会一个 14 一个 16。页面要整套样式就用这里的，
/// 只要一个数字（比如算某个盒子的高度）才用 [AppFont]。
///
/// **名字比槽位少，也比槽位多。** 少，是因为 Material 那 15 个槽位里有 6 个
/// 只是同一套数值挂了不同的名字：24 号加粗占了三个（displayMedium /
/// displaySmall / headlineLarge），12 号半粗也占三个（titleSmall /
/// labelMedium / labelSmall），14 号半粗占两个（titleMedium / labelLarge）。
/// 数值一样就没理由在页面里看起来不一样，于是合成一个名字——「差不多的东西
/// 不必特殊化」。多，是因为本项目确实用到几种 Material 没给槽位的搭配
/// （比如 24 号半粗），从前都靠页面自己在后面拧一次 `fontWeight`；那不是页面
/// 该操心的事，一并收进这张表。
///
/// **表里只放本项目用到的搭配。** 用到就给名字，没用到就不开口子——比如
/// 18 号加粗（`.fs-3 .fw-bold`）全站一处都没有，就不在这里出现，需要时照下面
/// 的格式补一行即可。这和字号表 [AppFont] 不开 `fs2` 是同一条规矩：表里的每
/// 一行都得有人在用，否则没人知道它到底该长什么样。
///
/// 排序跟着 [AppFont] 走：字号从小到大，同一档里字重从轻到重。
///
/// **为什么可以直接断言非空。** [ThemeData] 会把 15 个槽位全部填满（本项目
/// 没写的那部分由 Material 自带的 Typography 兜底），所以从
/// `Theme.of(context).textTheme` 取出来的槽位一定不是 null。断言收在这一层
/// 里，页面上就不必再跟着写一串 `!`。反过来说，这一层是给**主题里的**
/// TextTheme 用的，别拿它去点一个手工 `TextTheme()` 空壳。
extension TablerTextTheme on TextTheme {
  ///
  /// `.fs-6`：12 号常规，次要说明文字。
  TextStyle get fs6 => bodySmall!;

  ///
  /// `.fs-6 .fw-semibold`：12 号半粗，标签、单位与角标。
  TextStyle get fs6Semibold => titleSmall!;

  ///
  /// `.fs-6 .fw-bold`：12 号粗，小方块里的序号字母。
  ///
  /// 方块本身很小，半粗压不住，所以整档提到粗。Material 没有这个搭配的槽位，
  /// 这里在半粗那一档上换一次字重。
  TextStyle get fs6Bold => titleSmall!.copyWith(fontWeight: AppWeight.bold);

  ///
  /// `.fs-5`：14 号常规，本项目的正文档，也是 Flutter 的默认文字样式。
  TextStyle get fs5 => bodyMedium!;

  ///
  /// `.fs-5 .fw-semibold`：14 号半粗，按钮文字与顶栏数字。
  TextStyle get fs5Semibold => titleMedium!;

  ///
  /// `.fs-5 .fw-bold`：14 号粗，抽屉顶部的应用名。
  ///
  /// 和菜单项同字号，靠字重把它顶出来。Material 没有这个搭配的槽位。
  TextStyle get fs5Bold => bodyMedium!.copyWith(fontWeight: AppWeight.bold);

  ///
  /// `.fs-4`：16 号常规，比正文大半档的长文本。
  TextStyle get fs4 => bodyLarge!;

  ///
  /// `.fs-4 .fw-semibold`：16 号半粗，卡片标题与候选项正文。
  TextStyle get fs4Semibold => titleLarge!;

  ///
  /// `.fs-4 .fw-bold`：16 号粗，首页复习模块的标题与格子名称。
  ///
  /// 卡片里就这一行是主角，所以比同字号的候选项再重一档。
  /// Material 没有这个搭配的槽位。
  TextStyle get fs4Bold => titleLarge!.copyWith(fontWeight: AppWeight.bold);

  ///
  /// `.fs-3 .fw-semibold`：18 号半粗，题干与区块大标题。
  TextStyle get fs3Semibold => headlineSmall!;

  ///
  /// `.fs-1 .fw-semibold`：24 号半粗，问候语与随身听的单词。
  ///
  /// 这两处要的是「大而不吼」：字号到位，但不必像页面主标题那么重。
  /// Material 的 24 号只有加粗一种，所以这里换一次字重。
  TextStyle get fs1Semibold =>
      headlineLarge!.copyWith(fontWeight: AppWeight.semibold);

  ///
  /// `.fs-1 .fw-bold`：24 号加粗，页面级大标题与结算页主标题。
  TextStyle get fs1Bold => headlineLarge!;

  ///
  /// `.display-6`：40 号加粗，全站最大的一档，只给结算页的大数字。
  ///
  /// 不带字重后缀是照 Bootstrap 的规矩——`.display-*` 自带字重，
  /// 不需要再挂一个 `.fw-*`。
  TextStyle get display6 => displayLarge!;
}
