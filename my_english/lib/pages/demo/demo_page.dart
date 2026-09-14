// material.dart 提供页面、文本与对齐布局。
import 'package:flutter/material.dart';

// 引入应用设计令牌：颜色、字号、间距都从这套表取，明暗主题自动适配。
import '../../common/theme.dart';
// 引入复习模块共用的「上中下三段」页面框架与顶栏模板。
// 本页刻意复用它，让演示界面和正式复习模块的骨架完全一致，
// 以后往里塞组件时就是在「真机那个壳」里看效果，不用另起一套。
import '../../widgets/module_scaffold.dart';

///
/// 组件演示页（demo）。
///
/// 这个页面是专门为「开发、预览各类 UI 组件」准备的一个空壳。它的顶栏**完整复用**
/// 五个复习模块共用的 [ModuleHeader] 默认形态，从第一行到进度条和正式模块一模一样：
///
/// ```text
/// ┌──────────────────────────────────────────────┐
/// │  <   第 1 / 10          00:00                 │  ← 返回键 + 居中数字进度 + 右上角停留时间
/// ├──────────────────────────────────────────────┤
/// │ ███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │  ← 充当分割线的进度条
/// └──────────────────────────────────────────────┘
/// ```
///
/// 这套顶栏元素是模块框架的**默认件**，已经按真实模块长好；同时它们都可被替换，
/// 以还原不同模块的差异：
///
/// - 居中 `title` 默认是 [ModuleProgressLabel]（「第几个 / 总数」），
///   由 [current] / [total] 决定；
/// - 右上角 `trailing` 默认是 [ModuleTimeLabel]（停留时间），
///   可换成随身听那样的「设置键」或其它模块专属控件；
/// - 底部那条进度条由 [progress] 控制，传 `null` 就不画。
///
/// 正文区目前是空的（只有一行淡淡的占位提示），专门留给将来要演示的
/// 结算状态页等公共组件往里放。[body] 由调用方决定，不传则显示占位提示。
///
/// 入口目前挂在首页「开始复习」四个字上（临时演示入口），将来会换成正式的
/// 路由或调试菜单。
///
class DemoPage extends StatelessWidget {
  ///
  /// 创建一个演示页。
  ///
  /// 不传任何参数时，顶栏就是正式复习模块的默认形态：返回键 + 「1 / 10」数字进度
  /// + 「00:00」停留时间 + 一条进度条；正文显示占位提示。
  const DemoPage({
    this.current = 1,
    this.total = 10,
    this.timeText = '00:00',
    this.progress = 0.1,
    this.leading,
    this.trailing,
    this.title,
    this.body,
    super.key,
  });

  ///
  /// 顶栏居中数字进度的「当前第几个」（从 1 开始）。
  ///
  /// 默认 1；只有不传 [title] 时才有意义——它决定那行「第几个 / 总数」的左边数字。
  final int current;

  ///
  /// 顶栏居中数字进度的「总数」。
  ///
  /// 默认 10；只有不传 [title] 时才有意义。
  final int total;

  ///
  /// 顶栏右上角时间的文本（mm:ss 或 hh:mm:ss）。
  ///
  /// 默认「00:00」；只有不传 [trailing] 时才有意义。演示倒计时等场景可传别的值，
  /// 或直接传 [trailing] 整个换掉右侧插槽。
  final String timeText;

  ///
  /// 顶部进度条的完成比例（0～1）；传 `null` 表示这一屏顶栏不画进度条。
  ///
  /// 默认 0.1：留一点可见填充，明确告诉看的人「这是进度条的位置」。
  final double? progress;

  ///
  /// 左侧插槽：不传就是默认返回键（点一下退出 demo 回到首页）。
  ///
  /// 一般不需要动它；[ModuleHeader] 内部已经把默认值接好了。
  final Widget? leading;

  ///
  /// 右侧插槽：默认是 [ModuleTimeLabel]（停留时间）。
  ///
  /// 想还原「随身听右上角是设置键」这类差异时，
  /// 把对应组件传进来即可替换掉默认的时间文字。
  final Widget? trailing;

  ///
  /// 居中插槽：默认是 [ModuleProgressLabel]（「第几个 / 总数」）。
  ///
  /// 极少数演示场景若不需要数字进度，可传任意组件（比如一行标题文字）替换它。
  final Widget? title;

  ///
  /// 正文区要演示的组件；不传时显示一行淡色占位提示，表明这里「等待填充」。
  final Widget? body;

  ///
  /// 把顶栏（默认即模块框架）与空正文拼成一页。
  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return ModuleScaffold(
      // 顶栏完整复用模块框架，三个插槽都给了默认值：
      // 左=返回键（leading 不传走 ModuleHeader 内置默认）、
      // 中=数字进度、右=停留时间、下方=进度条。
      header: ModuleHeader(
        // 居中：默认是「第几个 / 总数」；调用方传了 title 就整个替换。
        title: title ?? ModuleProgressLabel(current: current, total: total),
        // 右侧：默认是停留时间；调用方传了 trailing 就替换（如设置键、倒计时）。
        trailing: trailing ?? ModuleTimeLabel(text: timeText),
        // 底部进度条：默认留一点填充以标示位置；传 null 就不画。
        progress: progress,
        // leading 不传，ModuleHeader 会自动补上返回键。
        leading: leading,
      ),
      // 正文：调用方传入的演示组件；没有就给一行占位提示，
      // 明确告诉看的人「这里还没放内容」。
      body: body ?? _DemoPlaceholder(tokens: tokens, textTheme: textTheme),
    );
  }
}

///
/// 正文占位提示：淡色居中一行字，表明这一屏的「正文区」当前是空的。
///
/// 单独抽成组件，是为了让 [DemoPage] 的 build 保持一眼能看完的清爽。
///
class _DemoPlaceholder extends StatelessWidget {
  ///
  /// 创建占位提示。
  const _DemoPlaceholder({required this.tokens, required this.textTheme});

  ///
  /// 当前主题色板，用于取次要文字色。
  final AppTokens tokens;

  ///
  /// 当前文字主题，用于取字号。
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      '演示区（正文待填充）',
      style: textTheme.fs5.copyWith(color: tokens.textSecondary),
    ),
  );
}
