// material.dart 提供布局、文字与可点击容器。
import 'package:flutter/material.dart';

// 引入应用设计令牌：颜色、字号、间距、圆角、图标与透明度都从这套表取，
// 明暗主题自动适配，和全站其它界面是同一套「语言」。
import '../common/theme.dart';
// 计时格式化（mm:ss），和顶栏右上角计时是同一个函数，保证口径一致。
import '../common/date.dart';
// 结算结果属于业务模型，页面只负责把它画出来。
import '../models/settlement.dart';

///
/// 结算组件的专属尺寸表。
///
/// 和页面那几张 Layout 表一样：这里的数字只在本文件里用，但都是「一处改、整片跟着
/// 变」的方寸，所以收在一起，界面代码里不再出现裸数字。
///
abstract final class SettlementSummaryLayout {
  ///
  /// 右侧难度按钮的可点击热区（正方形边长）。
  ///
  /// 同时充当「一行内容的总高度」：行里的文字、圆点都在这条高度里垂直居中，
  /// 所以按钮多高，这一行就有多高。
  static const double rowControlHeight = 36;

  ///
  /// 单个「最近表现」圆点的直径。
  static const double dotSize = 6;

  ///
  /// 圆点与圆点之间的间隙。
  static const double dotGap = 3;

  ///
  /// 5 颗圆点排成一行的总宽度：5 颗圆点 + 4 道缝。
  static const double dotsRowWidth = dotSize * 5 + dotGap * 4;

  ///
  /// 难度数字与中间箭头之间的距离。
  static const double difficultyArrowGap = AppSpace.p1;

  ///
  /// 「难度变化 + 圆点」这一列的宽度。
  ///
  /// 取圆点行的宽度再加一档基准间距：上面那行最宽的情形是「两位数 + 箭头 +
  /// 两位数」（约 49），比圆点行的 42 略宽，加 16 是给它留足余量，
  /// 免得列宽随数字位数抖动、各行右侧按钮对不齐。
  static const double difficultyColumnWidth = dotsRowWidth + AppSpace.p3;

  ///
  /// 难度变化那行文字与圆点之间的距离。
  static const double difficultyChangeGap = AppSpace.p1;

  ///
  /// 明细行之间那条分隔线的高度。
  ///
  /// 同时也是它的粗细：`Divider` 的 `height` 是整条线占的竖直空间，
  /// 与 `thickness` 取同一个值时，线本身既是 1px 也不额外撑高行距。
  static const double dividerHeight = AppStroke.thin;

  ///
  /// 统计胶囊里「变难 / 变易 / 不变 / 手动」四格之间那条竖线的宽度。
  static const double statDividerWidth = AppStroke.thin;

  ///
  /// 上面那条竖线的高度。
  ///
  /// 比一行数字加标签的总高略短，两端不顶到四格的边界，看起来是「分隔」而不是
  /// 「切成四块」。取 40 而不是跟着 [rowControlHeight]（36）：这一行上下都还有
  /// 胶囊自己的内边距，40 正好与左右两侧文字块的高度齐平。
  static const double statDividerHeight = 40;

  ///
  /// 明细行最左边那个对错图标的固定占位宽度。
  ///
  /// 图标本身是 [AppIcon.i20]（20），留 28 是为了让「绿勾 / 红叉」这一列在
  /// 所有行里占同样宽——否则不同行的单词会因为图标宽窄不同而左右错开。
  static const double resultIconWidth = 28;

  ///
  /// 手动改过难度的行，最左缘那颗标记短条的宽度。
  static const double manualMarkWidth = 3;

  ///
  /// 上面那颗标记短条的高度。
  ///
  /// 只占一行高度的一小段，垂直居中——比贴满整行的方条轻盈，
  /// 也不会被上下分割线切出直角。
  static const double manualMarkHeight = 16;

  ///
  /// 底部「再来一次 / 返回首页」那一行的高度。
  ///
  /// 左右两个按钮都贴满这条高度，上下边界完全一致；48 也高于
  /// [AppSize.touchTarget] 那条「手指可点的下限」。
  static const double actionRowHeight = 48;
}

///
/// 难度调整按钮在一轮循环里经过的三个状态，顺序固定。
///
/// 用户每点一次按钮，就沿这个顺序跳到下一个：
/// 不变 → 变难(+1) → 变易(-1) → 不变……如此循环，保证三种状态都能点到。
const List<DifficultyAdjust> _adjustCycle = [
  DifficultyAdjust.none,
  DifficultyAdjust.up,
  DifficultyAdjust.down,
];

///
/// 把当前状态推进到循环里的下一个状态。
DifficultyAdjust _nextAdjust(DifficultyAdjust current) {
  final i = _adjustCycle.indexOf(current);
  // 取模回到开头，形成闭环；indexOf 必然命中，所以不会越界。
  return _adjustCycle[(i + 1) % _adjustCycle.length];
}

///
/// 单个单词在结算时的展示数据。
///
/// 这一份是「只读输入」：由调用方（各复习模块）在练完一局后填好传进来。
/// 其中 [initialAdjust] 是系统根据本轮表现自动给出的难度结论，用户可以在
/// 页面里手动把它改掉——改过的痕迹由组件内部用 [SettlementSummary] 自己记。
class SettlementWordItem {
  ///
  /// 创建一条单词结算数据。
  const SettlementWordItem({
    required this.word,
    required this.isCorrect,
    required this.usedTime,
    required this.recentResults,
    this.difficultyBefore = 0,
    this.streak,
    this.initialAdjust = DifficultyAdjust.none,
  });

  ///
  /// 单词本身（英文）。
  final String word;

  ///
  /// 本轮是否答对：决定左侧对错圆形图标（绿勾 / 红叉）。
  final bool isCorrect;

  ///
  /// 这个单词本轮花了多久；为 `null` 时这一行**不显示用时**。
  ///
  /// 只有听音辨义和拼写巩固会给值——这两块的粒度就是「一个单词」，
  /// 掐表掐得准。词义连连和看义选词是按「含义」走的，一个单词会散在
  /// 好几条含义里，分不出它单独花了多久，所以直接留空不显示。
  final Duration? usedTime;

  ///
  /// 最近若干轮（最多 5 轮）的对错情况，用于底部那 5 个圆点。
  ///
  /// 列表里每个元素对应一轮：
  /// - `true`  该轮答对 → 绿色实心圆点；
  /// - `false` 该轮答错 → 红色实心圆点；
  /// - `null`  无数据 → 灰色空心圈。
  ///
  /// 顺序为「更早 → 本轮」：**最后一个元素就是本轮（最新一次）**，向左一轮比一轮旧。
  /// 长度不超过 5，不足 5 时**右侧**补灰色空圈——就像先在纸上画好 5 个空圈，
  /// 再从左到右把有数据的轮次填进去，所以空圈只可能出现在最右端。
  /// 这 5 个圆点和「用时」一样始终显示。
  final List<bool?> recentResults;

  ///
  /// 本轮复习**开始前**这个单词的难度值。
  ///
  /// 生活化解释：难度是一个从 0 开始往上走的整数，数字越大表示这个词越「难啃」，
  /// 复习时会排得越靠前。结算页每一行都要显示「难度从多少变成多少」，
  /// 左边这个数就是「变之前」的那一个；「变之后」由它加上当前难度调整算出。
  ///
  /// 默认 0（新加进来的单词难度就是 0）。
  final int difficultyBefore;

  ///
  /// 连续答对次数，**仅答对时出现**；答错为 null。
  final int? streak;

  ///
  /// 系统自动给出的难度结论；用户手动调整前的初始值。
  final DifficultyAdjust initialAdjust;

  ///
  /// 按给定的难度调整，算出这一行**调整之后**的难度值。
  ///
  /// 难度最小为 0：已经是 0 的词再点「变易」不会变成 -1，而是停在 0。
  int difficultyAfter(DifficultyAdjust adjust) {
    final after = difficultyBefore + difficultyAdjustDelta(adjust);
    return after < 0 ? 0 : after;
  }
}

///
/// 结算状态页公共组件。
///
/// 这是给四个复习模块共用的「练完那一屏」明细区，从上到下依次是：
///
/// 1. **统计胶囊**（白底、带 1px 边框、大圆角）：居中主宣告「本轮复习结束」，其下
///    一行 `共 N 词 · 答对 X · 答错 Y · 实际用时 hh:mm:ss` 对错统计（对绿错红）；
///    一条分隔线之下是四个等分区域「变难 / 变易 / 不变 / 手动」——前三个由下方列表里
///    每个单词当前难度状态实时汇总，「手动」是用户在本页点过调整按钮的单词数；
/// 2. **单词明细长列表**（白底、带 1px 边框、圆角，可滚动）：整行单排——对错圆形
///    图标（无圆环的纯对勾 / 纯叉，成功绿 / 危险红）、单词（过长省略号收尾）、用时、
///    难度变化列（**上面一行是「变之前 → 变之后」的难度数字，下面一行是最近 5 轮
///    对错圆点**；两行合起来仍是原来的行高）、难度调整按钮（纯图标，三态可循环切换）。
///    手动改过难度的行，最左缘有一颗圆角品牌蓝短条作标记；
/// 3. **底部「再来一次」+「返回首页」两个按钮**：样式与听音辨义练完一题后的
///    「再试一次 / 下一题」完全一致——左为描边样式的「再来一次」、右为品牌蓝实心的
///    「返回首页」。[onRetry] 触发再来一次（整轮重做），[onConfirm] 触发返回首页；
///    两个都不传时，在 demo 预览里自动返回上一屏。
///
/// 它是「状态自管」的：内部按列表维护每一行的当前难度与是否手动改过，
/// 点按钮即时刷新本行与顶部胶囊。需要把手动结果回写库时，传 [onAdjust]
/// 回调即可，组件不关心持久化细节。
///
/// 目前通过 `DemoPage` 的 `body` 进入预览（首页「开始复习」临时入口）。
///
class SettlementSummary extends StatefulWidget {
  ///
  /// 创建结算状态组件。
  ///
  /// [items] 是本次会话所有单词的结算数据；[onAdjust] 在用户手动调整某行难度时
  /// 回调（index 为行号，adjust 为调整后的值），不传则只在页面内生效。
  const SettlementSummary({
    required this.items,
    this.aggregatedWordElapsed,
    this.showTotalElapsed = true,
    this.onAdjust,
    this.onRetry,
    this.onConfirm,
    super.key,
  });

  ///
  /// 本次会话的单词结算数据。
  final List<SettlementWordItem> items;

  ///
  /// 听音辨义、拼写巩固中每个单词实际计时的汇总。
  ///
  /// 这不是右上角的页面停留时间，而是把结算明细里的单词用时相加。词义连连
  /// 和看义选词无法把时间可靠地切到单词粒度，因此不传此值。
  final Duration? aggregatedWordElapsed;

  /// 是否在统计胶囊中显示本轮实际用时。
  ///
  /// 演示页默认显示；词义连连和看义选词传 false，因为它们无法把时间可靠
  /// 地拆到单词层级。
  final bool showTotalElapsed;

  ///
  /// 用户手动调整某行难度后的通知；由调用方决定是否落库。
  final void Function(int index, DifficultyAdjust adjust)? onAdjust;

  ///
  /// 底部「再来一次」按钮的点击回调：整轮重做一遍。
  ///
  /// 不传时（如 demo 预览）默认返回上一屏——demo 没有真实一轮可重开，
  /// 真实模块接入后必须传入它来重启本局会话。
  final VoidCallback? onRetry;

  ///
  /// 底部「返回首页」按钮的点击回调；不传则在 demo 预览里自动返回上一屏。
  final VoidCallback? onConfirm;

  ///
  /// 演示用示例数据：覆盖对错、历史轮数多寡、三种初始难度，方便在 demo 页直接看效果。
  factory SettlementSummary.demo() =>
      const SettlementSummary(items: _demoItems);

  @override
  State<SettlementSummary> createState() => _SettlementSummaryState();
}

///
/// 组件内部状态：每一行「当前难度」和「是否被手动改过」。
///
/// 初始化时从 [SettlementWordItem.initialAdjust] 拷贝一份；用户点按钮只改这份
/// 内存副本并触发重绘，因此顶部统计胶囊能跟着实时变。
class _SettlementSummaryState extends State<SettlementSummary> {
  ///
  /// 每一行当前的难度状态（初始 = 系统自动结论）。
  late final List<DifficultyAdjust> _adjusts;

  @override
  void initState() {
    super.initState();
    // 从输入数据拷一份难度初值；这是组件内部唯一可变的真相来源。
    _adjusts = widget.items.map((e) => e.initialAdjust).toList();
  }

  ///
  /// 用户点某行按钮：沿循环切到下一态。
  void _cycle(int index) {
    setState(() {
      _adjusts[index] = _nextAdjust(_adjusts[index]);
    });
    // 把结果上报给调用方（如需要落库）；不传回调就只更新界面。
    widget.onAdjust?.call(index, _adjusts[index]);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    // 实时汇总四种计数，顶部胶囊依赖它们。
    var harder = 0; // 难度上升 = 变难
    var easier = 0; // 难度下降 = 变易
    var unchanged = 0; // 不变
    var manual = 0; // 当前被手动改离「初始值」的单词数
    for (var i = 0; i < _adjusts.length; i++) {
      switch (_adjusts[i]) {
        case DifficultyAdjust.up:
          harder++;
        case DifficultyAdjust.down:
          easier++;
        case DifficultyAdjust.none:
          unchanged++;
      }
      // 「手动」= 当前难度与系统初始结论不同的单词数：
      // 改离原样 +1、切回原样 -1，所以直接比当前值和初值即可，无需额外标记。
      if (_adjusts[i] != widget.items[i].initialAdjust) manual++;
    }

    // 大字报下方那一行小统计要用到的三个数：总词数、答对数、答错数。
    final totalCount = widget.items.length;
    var correctCount = 0;
    for (final item in widget.items) {
      if (item.isCorrect) correctCount++;
    }
    final wrongCount = totalCount - correctCount;

    // 顶部「实际用时」只在单词级计时模块显示：它是所有单词用时的汇总，
    // 不再拿右上角的页面停留时间代替。演示页未传值时保留明细求和回退。
    final totalUsedSeconds = !widget.showTotalElapsed
        ? null
        : widget.aggregatedWordElapsed?.inSeconds ??
              widget.items.fold<int>(
                0,
                (sum, item) => sum + (item.usedTime?.inSeconds ?? 0),
              );

    // 提前把列表的「行 + 分割线」拼好，下面布局直接复用。
    final listChildren = <Widget>[];
    for (var i = 0; i < widget.items.length; i++) {
      // 行与行之间插入 1px 分割线（第一个行前不加）。
      if (i > 0) {
        listChildren.add(
          Divider(
            height: SettlementSummaryLayout.dividerHeight,
            thickness: AppStroke.thin,
            color: tokens.border,
            indent: AppSpace.p3,
            endIndent: AppSpace.p3,
          ),
        );
      }
      listChildren.add(
        _SettlementRow(
          item: widget.items[i],
          adjust: _adjusts[i],
          onCycle: () => _cycle(i),
          tokens: tokens,
          textTheme: textTheme,
        ),
      );
    }

    // 上：统计胶囊（白底卡片）；中：单词列表（白底圆角卡，可滚动）；
    // 下：底部「确定」按钮（带呼吸与安全距离）。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部统计胶囊：一张白底带边框的卡，从上到下依次是「本轮结束」宣告标题、
        // 一行对错统计（对绿错红）、分隔线、四个等分的难度计数（变难/变易/不变/手动）。
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.pBase,
            AppSpace.pBase,
            AppSpace.pBase,
            AppSpace.p0,
          ),
          child: _StatCapsule(
            counts: [harder, easier, unchanged, manual],
            labels: const ['变难', '变易', '不变', '手动'],
            totalCount: totalCount,
            correctCount: correctCount,
            wrongCount: wrongCount,
            totalUsedSeconds: totalUsedSeconds,
            tokens: tokens,
            textTheme: textTheme,
          ),
        ),

        // 单词明细列表：整体包进一张白底、无边框、圆角的卡片里。
        // 卡片外留 pBase 外边距；卡片内**顶部/底部各只留 p2**（比左右 p3 收一档），
        // 让首行/末行到卡片边缘的留白与左右一致——这正是上一轮「上下来回比左右宽」
        // 的根因：原来整段居中，内容不足一屏时把空白全堆在上下，显得上下比左右胖。
        // 现在改成顶对齐 + 小号上下内边距：首末行上下留白 = p2(列表)+p2(行)=16，
        // 与左右 p3(16) 齐平。
        Expanded(
          child: Padding(
            // 外边距 pBase：让白卡与四周留出呼吸空间。
            padding: const EdgeInsets.all(AppSpace.pBase),
            child: Container(
              decoration: BoxDecoration(
                // 白底 + 大圆角，与顶部统计胶囊同款描边，成组成套。
                color: tokens.card,
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                border: Border.all(color: tokens.rowBorder, width: AppStroke.thin),
              ),
              // 裁掉超出圆角的内容（滚动时子项不会顶到圆角外）。
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
                child: SingleChildScrollView(
                  // 卡片内上下只留 p2，使首/末行与左右留白观感一致。
                  // padding: const EdgeInsets.symmetric(vertical: AppSpace.p0),
                  child: Column(
                    // 顶对齐：内容短则底部留白，长则滚动。
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: listChildren,
                  ),
                ),
              ),
            ),
          ),
        ),

        // 底部「再来一次」+「返回首页」：左描边、右蓝实心，样式与听音辨义
        // 「再试一次 / 下一题」一致。底部安全距离由外层 ModuleScaffold 的
        // SafeArea 处理（默认已避让底部手势区），这里只补 pBase 呼吸。
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.pBase,
            AppSpace.p0,
            AppSpace.pBase,
            AppSpace.pBase,
          ),
          child: _BottomActions(
            onRetry: widget.onRetry,
            onBackHome: widget.onConfirm,
            tokens: tokens,
            textTheme: textTheme,
          ),
        ),
      ],
    );
  }
}

///
/// 顶部统计胶囊：一张白底带边框的卡，把「完成概况」收进一处。
///
/// 自上而下三段：
/// 1. 居中主宣告「本轮复习结束」；
/// 2. 一行对错统计（`共 N 词 · 答对 X · 答错 Y · 实际用时 hh:mm:ss`，对绿错红）；
/// 3. 分隔线之下四个等分区域（变难 / 变易 / 不变 / 手动），每区上数字、下文字，
///    数字颜色按各自语义取（变难红 / 变易绿 / 不变灰 / 手动有改动才点亮品牌蓝）。
class _StatCapsule extends StatelessWidget {
  ///
  /// 创建胶囊。
  const _StatCapsule({
    required this.counts,
    required this.labels,
    required this.totalCount,
    required this.correctCount,
    required this.wrongCount,
    this.totalUsedSeconds,
    required this.tokens,
    required this.textTheme,
  });

  ///
  /// 四个数字，顺序与 [labels] 对齐（变难/变易/不变/手动）。
  final List<int> counts;

  ///
  /// 四个文字标签。
  final List<String> labels;

  ///
  /// 本轮单词总数，用于标题下方那行对错统计。
  final int totalCount;

  ///
  /// 本轮答对数（统计行里标绿）。
  final int correctCount;

  ///
  /// 本轮答错数（统计行里标红）。
  final int wrongCount;

  ///
  /// 本轮所有单词用时的汇总（秒）；与右上角页面停留时间不是同一个口径。
  ///
  /// 只有听音辨义和拼写巩固会传值。词义连连、看义选词不显示该统计。
  final int? totalUsedSeconds;

  ///
  /// 当前主题色板。
  final AppTokens tokens;

  ///
  /// 当前文字主题。
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    // 每个区域数字的颜色：变难红、变易绿、不变=与「不变」按钮同灰、
    // 手动>0=进度条蓝、=0=灰。和全站语义色（危险/成功/品牌）保持一致。
    Color numberColor(int i, int count) {
      switch (i) {
        case 0:
          return AppTokens.danger; // 变难
        case 1:
          return AppTokens.success; // 变易
        case 2:
          return tokens.textSecondary; // 不变（与「不变」按钮同色）
        case 3:
          // 手动：有改动才点亮成进度条蓝，否则保持灰。
          return count > 0 ? AppTokens.primary : tokens.textSecondary;
        default:
          return tokens.text;
      }
    }

    return Container(
      // 白底 + 大圆角；与下方单词列表卡同款描边，成组成套。
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        border: Border.all(color: tokens.rowBorder, width: AppStroke.thin),
      ),
      // 内部留白 pBase，内容不贴卡片边缘。
      padding: const EdgeInsets.all(AppSpace.pBase),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpace.p2),
          // 主宣告：本轮复习结束，整体居中。
          Text(
            '本轮复习结束',
            style: textTheme.fs1Bold.copyWith(color: tokens.text),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpace.p3),
          if (totalUsedSeconds case final int seconds) ...[
            Text(
              // 满 1 小时显示 hh:mm:ss，否则只显示 mm:ss；这里的秒数来自所有单词汇总。
              "实际用时 ${formatTimerSeconds(seconds)}",
              style: textTheme.fs5.copyWith(color: tokens.text),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.p3),
          ],
          // 对错统计一行：总词数、对错（对绿错红），整体居中。
          Text.rich(
            TextSpan(
              style: textTheme.fs5.copyWith(color: tokens.textSecondary),
              children: [
                const TextSpan(text: '共 '),
                TextSpan(
                  text: '$totalCount',
                  style: textTheme.fs5Semibold.copyWith(color: tokens.text),
                ),
                const TextSpan(text: ' 词 · 答对 '),
                TextSpan(
                  text: '$correctCount',
                  style: textTheme.fs5Semibold.copyWith(
                    color: AppTokens.success,
                  ),
                ),
                const TextSpan(text: ' · 答错 '),
                TextSpan(
                  text: '$wrongCount',
                  style: textTheme.fs5Semibold.copyWith(
                    color: AppTokens.danger,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          // 分隔线：统计行与下方四格之间，上下各留 p2 呼吸。
          const SizedBox(height: AppSpace.p4),
          Divider(
            height: SettlementSummaryLayout.dividerHeight,
            thickness: AppStroke.thin,
            color: tokens.border,
          ),
          const SizedBox(height: AppSpace.p2),
          // 四格：等宽，数字与文字都居中，区域之间用 1px 竖线分隔。
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < counts.length; i++) ...[
                // 区域之间的竖线（第一个区域前不加）。
                if (i > 0)
                  Container(
                    width: SettlementSummaryLayout.statDividerWidth,
                    height: SettlementSummaryLayout.statDividerHeight,
                    color: tokens.border,
                  ),
                // Expanded 让四区等宽。
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 上面的数字，按区域语义上色。
                      Text(
                        '${counts[i]}',
                        style: textTheme.fs1Bold.copyWith(
                          color: numberColor(i, counts[i]),
                        ),
                      ),
                      const SizedBox(height: AppSpace.p1),
                      // 下面的文字：小号次要色。
                      Text(
                        labels[i],
                        style: textTheme.fs6.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

///
/// 把难度三态翻译成「按钮外观」（图标 + 文案 + 颜色）。
///
/// 颜色语义：上升=红（对用户更难，需要多练）、下降=绿（已掌握）、不变=灰（中性）。
/// 单独抽成函数，按钮和统计胶囊之外任何地方想取同款外观都走这一处。
(IconData, String, Color) _adjustVisual(
  DifficultyAdjust adjust,
  AppTokens tokens,
) {
  switch (adjust) {
    case DifficultyAdjust.up:
      return (AppGlyph.difficultyUp, '+1', AppTokens.danger);
    case DifficultyAdjust.down:
      return (AppGlyph.difficultyDown, '-1', AppTokens.success);
    case DifficultyAdjust.none:
      return (AppGlyph.difficultyNone, '0', tokens.textSecondary);
  }
}

///
/// 把「最近轮次对错」列表规整成固定 5 个状态，顺序 = 从旧到新，本轮在最右。
///
/// 生活化解释：先在纸上画好 5 个空心圈，再把练过的轮次**从左到右**填进去，
/// 最右边那个是刚刚这一轮。练过的轮次不够 5 个时，右边剩下的就是空心圈。
///
/// 例如只练过 3 轮（最早错、中间对、本轮对），返回
/// `[错, 对, 对, null, null]` → 显示「红 绿 绿 空 空」。
List<bool?> _normalizeRecentResults(List<bool?> raw) {
  // 最后一个是本轮（最新），所以超过 5 轮时保留**最后** 5 个（最近的 5 轮）。
  if (raw.length >= 5) return raw.sublist(raw.length - 5);
  // 不足 5 轮：在右侧补灰色空圈（null），保证总数恒为 5。
  return <bool?>[...raw, for (var i = raw.length; i < 5; i++) null];
}

///
/// 单个圆点的三态外观。
///
/// - `null`：无数据 → 透明填充 + 细描边，看起来是空心灰圈；
/// - `true` ：答对 → 绿色实心（和左侧绿勾同一套语义色）；
/// - `false`：答错 → 红色实心（和左侧红叉同一套语义色）。
Widget _buildRecentDot(bool? result, AppTokens tokens) {
  if (result == null) {
    return Container(
      width: SettlementSummaryLayout.dotSize,
      height: SettlementSummaryLayout.dotSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.transparent,
        border: Border.all(color: tokens.border, width: AppStroke.thin),
      ),
    );
  }
  return Container(
    width: SettlementSummaryLayout.dotSize,
    height: SettlementSummaryLayout.dotSize,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: result ? AppTokens.success : AppTokens.danger,
    ),
  );
}

///
/// 5 个圆点排成一行；圆点之间留 3px 间隙，整体不撑高元数据行。
Widget _buildRecentDots(List<bool?> raw, AppTokens tokens) {
  final states = _normalizeRecentResults(raw);
  return Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      for (var i = 0; i < states.length; i++) ...[
        if (i > 0) const SizedBox(width: SettlementSummaryLayout.dotGap),
        _buildRecentDot(states[i], tokens),
      ],
    ],
  );
}

///
/// 「难度从多少变成多少」这一行小字，如 `2 ▸ 3`。
///
/// 生活化解释：左边的数是本轮开始时的难度，右边的数是按当前按钮状态算出来的
/// 新难度——点一下按钮，右边这个数会跟着变，用户点之前就能看见「点下去会变成几」。
///
/// 中间的箭头用 Tabler 的图标（[AppGlyph.difficultyArrow]）而不是「→」这个字符：
/// 字符跟着文字基线走，和两个数字比会明显偏下；图标在自己的方框里是垂直居中的，
/// 配上 `CrossAxisAlignment.center` 就和左右两个数字齐平了。
Widget _buildDifficultyChange(
  int before,
  int after,
  DifficultyAdjust adjust,
  AppTokens tokens,
  TextTheme textTheme,
) {
  // 只取颜色，图标与本行无关（图标由右侧按钮画）。
  final (_, _, color) = _adjustVisual(adjust, tokens);
  return Row(
    mainAxisSize: MainAxisSize.min,
    // 三个元素（数字、箭头、数字）按中心线对齐，箭头才不会偏上偏下。
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      // 左边「变之前」：最小号次要色，不抢单词本身的注意力。
      Text(
        '$before',
        style: textTheme.fs6.copyWith(color: tokens.textSecondary),
      ),
      const SizedBox(width: SettlementSummaryLayout.difficultyArrowGap),
      Icon(
        AppGlyph.difficultyArrow,
        size: AppIcon.i14,
        color: tokens.textSecondary,
      ),
      const SizedBox(width: SettlementSummaryLayout.difficultyArrowGap),
      // 右边「变之后」：加粗并按方向上色（变难红 / 变易绿 / 不变灰），
      // 是这一列唯一被强调的数字。
      Text('$after', style: textTheme.fs6Semibold.copyWith(color: color)),
    ],
  );
}

///
/// 右侧那一列：**上面一行难度变化、下面一行 5 个圆点**。
///
/// 生活化解释：先在纸上画好 5 个空心圈表示最近几轮的表现，圈的正上方再写一行
/// 「难度从几变成几」——两件事上下叠着放，一行里就能同时看到「最近练得怎么样」
/// 和「难度要往哪边走」。
///
/// 两行合起来的高度固定等于右侧按钮的高度（[SettlementSummaryLayout.rowControlHeight]），
/// 内容在这个高度里垂直居中——所以这一列变成两行之后，单词行的总高度一点没变，
/// 只是把原来空着的上下余量用上了。列宽也写成固定值（见该表的说明），
/// 各行的按钮才不会随数字位数左右抖动。
Widget _buildDifficultyColumn(
  SettlementWordItem item,
  DifficultyAdjust adjust,
  AppTokens tokens,
  TextTheme textTheme,
) => SizedBox(
  height: SettlementSummaryLayout.rowControlHeight,
  width: SettlementSummaryLayout.difficultyColumnWidth,
  child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _buildDifficultyChange(
        item.difficultyBefore,
        item.difficultyAfter(adjust),
        adjust,
        tokens,
        textTheme,
      ),
      const SizedBox(height: SettlementSummaryLayout.difficultyChangeGap),
      // 最近 5 轮对错圆点：始终显示，本轮在最右，向左一轮比一轮旧。
      _buildRecentDots(item.recentResults, tokens),
    ],
  ),
);

///
/// 单词明细的一行：左右三列。
class _SettlementRow extends StatelessWidget {
  ///
  /// 创建一行。
  const _SettlementRow({
    required this.item,
    required this.adjust,
    required this.onCycle,
    required this.tokens,
    required this.textTheme,
  });

  ///
  /// 这一行的单词数据。
  final SettlementWordItem item;

  ///
  /// 这一行当前的难度状态（来自组件内部状态）。
  final DifficultyAdjust adjust;

  ///
  /// 点击右侧按钮：请求切到下一难度态。
  final VoidCallback onCycle;

  ///
  /// 当前主题色板。
  final AppTokens tokens;

  ///
  /// 当前文字主题。
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    // 手动改过难度 = 当前难度 ≠ 系统初始结论；这类行左侧要有一颗圆角蓝条标记。
    final manual = adjust != item.initialAdjust;

    // 整张列表已包在白底圆角卡里，这里不再各自成卡，只负责一行内容 + 留白。
    // 整行从左到右：对错图标（无圆环的纯对勾 / 纯叉） → 单词 → 用时 → 最近 5 轮圆点 → 难度按钮。
    // 用 Stack 是因为手动蓝条要贴在行的最左缘（左内边距外侧），若排进 Row
    // 的内容流会把文字整体右推，观感不一致。
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.p3,
            vertical: AppSpace.p2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 对错图标，固定宽度 28：直接取「无圆环」的纯对勾 / 纯叉版本（正式样式）。
              SizedBox(
                width: SettlementSummaryLayout.resultIconWidth,
                child: Icon(
                  item.isCorrect ? AppGlyph.correct : AppGlyph.wrong,
                  size: AppIcon.i20,
                  // 答对错用成功绿 / 危险红，一眼区分。
                  color: item.isCorrect ? AppTokens.success : AppTokens.danger,
                ),
              ),
              const SizedBox(width: AppSpace.p1),
              // 单词：吃掉中间剩余宽度，过长时用省略号收尾，保证右侧内容不换行。
              Expanded(
                child: Text(
                  item.word,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.fs4Semibold,
                ),
              ),
              const SizedBox(width: AppSpace.p1),
              // 用时（如 00:12）；没有单词级计时的模块整列不显示。
              if (item.usedTime case final Duration usedTime) ...[
                Text(
                  formatTimerSeconds(usedTime.inSeconds),
                  style: textTheme.fs5.copyWith(color: tokens.textSecondary),
                ),
                const SizedBox(width: AppSpace.p3),
              ],
              // 难度变化 + 最近 5 轮对错圆点（上下两行，整体高度与按钮一致）。
              _buildDifficultyColumn(item, adjust, tokens, textTheme),
              const SizedBox(width: AppSpace.p2),
              // 难度调整按钮（纯图标，三态可循环切换）。
              _DifficultyButton(adjust: adjust, onTap: onCycle, tokens: tokens),
            ],
          ),
        ),
        // 手动改过的行：最左缘一条 3px 宽、两端全圆的品牌蓝短条（小胶囊），
        // 垂直居中只占一行高度的一小段——比贴满整行的方条更轻盈，也不会被
        // 上下分割线切出直角。
        if (manual)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                width: SettlementSummaryLayout.manualMarkWidth,
                height: SettlementSummaryLayout.manualMarkHeight,
                decoration: BoxDecoration(
                  color: AppTokens.primary,
                  borderRadius: BorderRadius.circular(AppRadius.roundedPill),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

///
/// 右侧难度调整按钮：圆角、三态，点一下循环切换。
class _DifficultyButton extends StatelessWidget {
  ///
  /// 创建按钮。
  const _DifficultyButton({
    required this.adjust,
    required this.onTap,
    required this.tokens,
  });

  ///
  /// 当前显示的状态。
  final DifficultyAdjust adjust;

  ///
  /// 点击回调。
  final VoidCallback onTap;

  ///
  /// 当前主题色板。
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    // 根据状态取图标与颜色，三态外观只此一处定义（纯图标，不再带文字与底框）。
    final (icon, _, color) = _adjustVisual(adjust, tokens);
    return SizedBox(
      // 固定可点击热区，保证三种状态的图标对齐一致；同时也是整行内容的基准高度。
      width: SettlementSummaryLayout.rowControlHeight,
      height: SettlementSummaryLayout.rowControlHeight,
      child: Material(
        // 完全透明：不要任何填充与描边，只保留点击水波纹。
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.rounded),
        ),
        // InkWell 提供点击水波纹，并被 Material 的圆角裁剪。
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.rounded),
          onTap: onTap,
          child: Center(
            // 纯图标：升=红（变难）、降=绿（变易）、不变=灰（中性）。
            child: Tooltip(
              message: switch (adjust) {
                DifficultyAdjust.up => '变难',
                DifficultyAdjust.down => '变易',
                DifficultyAdjust.none => '不变',
              },
              child: Icon(icon, size: AppIcon.i20, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

///
/// 底部操作区：左「再来一次」+ 右「返回首页」两个按钮。
///
/// 样式完全对齐听音辨义练完一题后的「再试一次 / 下一题」：
/// - 左侧「再来一次」：描边样式（[OutlinedButton]），次要操作；
/// - 右侧「返回首页」：品牌蓝实心（[FilledButton]），主操作。
/// 两个按钮各占一半宽度，中间用 [AppSpace.p3] 留间距，整行高 48。
/// [onRetry] 不传时（如 demo 预览）默认返回上一屏，真实模块接入后由它重开本局。
class _BottomActions extends StatelessWidget {
  ///
  /// 创建底部操作区。
  const _BottomActions({
    required this.onRetry,
    required this.onBackHome,
    required this.tokens,
    required this.textTheme,
  });

  ///
  /// 「再来一次」点击回调：整轮重做。
  final VoidCallback? onRetry;

  ///
  /// 「返回首页」点击回调。
  final VoidCallback? onBackHome;

  ///
  /// 当前主题色板（主色取 [AppTokens.primary]）。
  final AppTokens tokens;

  ///
  /// 当前文字主题。
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    // 整行固定高度，左右两个按钮上下边界完全一致。
    return SizedBox(
      width: double.infinity,
      height: SettlementSummaryLayout.actionRowHeight,
      child: Row(
        children: [
          // 左半：次要操作「再来一次」，把整轮退回初始状态重做。
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('settlement-retry'),
              onPressed: onRetry ?? () => Navigator.of(context).maybePop(),
              // Tabler 的刷新图标表达「重来一遍」，与听音辨义「再试一次」一致。
              icon: const Icon(AppGlyph.retry, size: AppIcon.i16),
              label: const Text('再来一次'),
              style: OutlinedButton.styleFrom(
                // 贴满外层高度，无额外内边距；描边与圆角继承主题次要按钮样式。
                minimumSize: const Size(
                  0,
                  SettlementSummaryLayout.actionRowHeight,
                ),
                padding: EdgeInsets.zero,
                textStyle: textTheme.fs5Semibold,
              ),
            ),
          ),
          // 两个按钮之间的固定间距，复用候选区与操作区的同一套尺寸。
          const SizedBox(width: AppSpace.p3),
          // 右半：主操作「返回首页」，蓝色实心。
          Expanded(
            child: FilledButton.icon(
              key: const Key('settlement-back-home'),
              onPressed: onBackHome ?? () => Navigator.of(context).maybePop(),
              // 房子图标表达「回到首页」。
              icon: const Icon(AppGlyph.home, size: AppIcon.i16),
              label: const Text('返回首页'),
              style: FilledButton.styleFrom(
                // 贴满外层高度，无额外内边距；蓝底白字与圆角继承主题主按钮样式。
                minimumSize: const Size(
                  0,
                  SettlementSummaryLayout.actionRowHeight,
                ),
                padding: EdgeInsets.zero,
                textStyle: textTheme.fs5Semibold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

///
/// 演示用示例数据：10 个单词，覆盖对错、历史轮数多寡、三种初始难度、一位/两位难度值；
/// 每个 recentResults **最后一个 = 本轮**，往左一轮比一轮旧，空圈只出现在最右。
const List<SettlementWordItem> _demoItems = [
  SettlementWordItem(
    word: 'apple',
    isCorrect: true,
    usedTime: Duration(seconds: 12),
    difficultyBefore: 2,
    streak: 3,
    // 满 5 轮，从左到右：上4错、上3对、上2错、上1对、本轮对。
    recentResults: [false, true, false, true, true],
  ),
  SettlementWordItem(
    word: 'banana',
    isCorrect: true,
    usedTime: Duration(seconds: 8),
    difficultyBefore: 4,
    streak: 5,
    initialAdjust: DifficultyAdjust.down,
    // 满 5 轮且全对。
    recentResults: [true, true, true, true, true],
  ),
  SettlementWordItem(
    word: 'computer',
    isCorrect: false,
    usedTime: Duration(seconds: 25),
    difficultyBefore: 1,
    initialAdjust: DifficultyAdjust.up,
    // 满 5 轮，从左到右：上4错、上3错、上2对、上1错、本轮错。
    recentResults: [false, false, true, false, false],
  ),
  SettlementWordItem(
    word: 'dictionary',
    isCorrect: true,
    usedTime: Duration(seconds: 15),
    // 难度 0：再点「变易」也不会变成 -1，用来验证下限。
    difficultyBefore: 0,
    streak: 2,
    // 含本轮共 4 轮：上3对、上2对、上1错、本轮对，最右 1 颗空圈。
    recentResults: [true, true, false, true, null],
  ),
  SettlementWordItem(
    word: 'elephant',
    isCorrect: true,
    usedTime: Duration(seconds: 19),
    difficultyBefore: 3,
    streak: 4,
    initialAdjust: DifficultyAdjust.up,
    // 满 5 轮，从左到右：上4对、上3错、上2对、上1对、本轮对。
    recentResults: [true, false, true, true, true],
  ),
  SettlementWordItem(
    word: 'furniture',
    isCorrect: false,
    usedTime: Duration(seconds: 31),
    // 两位数难度：用来验证这一列不会把右侧按钮挤歪。
    difficultyBefore: 12,
    // 含本轮共 4 轮：上3对、上2错、上1对、本轮错，最右 1 颗空圈。
    recentResults: [true, false, true, false, null],
  ),
  SettlementWordItem(
    word: 'gorgeous',
    isCorrect: true,
    usedTime: Duration(seconds: 9),
    difficultyBefore: 1,
    streak: 1,
    initialAdjust: DifficultyAdjust.down,
    // 模拟「hello」：有史以来第一次练（本轮对）→ 绿 空 空 空 空。
    recentResults: [true, null, null, null, null],
  ),
  SettlementWordItem(
    word: 'hospital',
    isCorrect: true,
    usedTime: Duration(seconds: 14),
    difficultyBefore: 6,
    streak: 6,
    // 满 5 轮且全对。
    recentResults: [true, true, true, true, true],
  ),
  SettlementWordItem(
    word: 'island',
    isCorrect: false,
    usedTime: Duration(seconds: 22),
    difficultyBefore: 3,
    initialAdjust: DifficultyAdjust.down,
    // 含本轮共 4 轮：上3错、上2对、上1错、本轮错，最右 1 颗空圈。
    recentResults: [false, true, false, false, null],
  ),
  SettlementWordItem(
    word: 'journey',
    isCorrect: true,
    usedTime: Duration(seconds: 11),
    difficultyBefore: 2,
    streak: 3,
    // 模拟「world」：此前练过 2 次 + 本轮共 3 轮全对 → 绿 绿 绿 空 空。
    recentResults: [true, true, true, null, null],
  ),
];
