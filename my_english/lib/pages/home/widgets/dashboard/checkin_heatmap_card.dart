// material.dart 提供布局、文字与异步状态组件。
import 'package:flutter/material.dart';
// dart:async 提供 unawaited，用于显式声明“这个异步任务不需要等它”。
import 'dart:async';
// tabler_icons_plus 提供火焰与左右箭头图标。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入设计稿色板令牌。
import '../../../../common/theme.dart';
// 引入默写记录 Store：按天的复习量聚合查询走这里。
import '../../../../store/record.dart';

///
/// 打卡质量分档：色块只保留 4 档（未复习 + 三级蓝色），与下方图例一一对应。
/// 原型原有 lvl-0 ~ lvl-4 五档，按需求把中间的 lvl-3 并入"达标"档收敛为 4 档。
///
enum CheckinLevel {
  /// 未复习（灰，对应原型 lvl-0）。
  zero,

  /// 少量/未达标（浅蓝，对应原型 lvl-1）。
  one,

  /// 达标（中蓝，对应原型 lvl-2/lvl-3 合并）。
  two,

  /// 超额完成（深蓝，对应原型 lvl-4）。
  three,
}

///
/// 为分档补充对应颜色。
///
extension CheckinLevelColor on CheckinLevel {
  /// 读取对应令牌色。
  Color color(AppTokens tokens) => switch (this) {
    CheckinLevel.zero => tokens.checkinLevel0,
    CheckinLevel.one => tokens.checkinLevel1,
    CheckinLevel.two => tokens.checkinLevel2,
    CheckinLevel.three => tokens.checkinLevel4,
  };

  /// 中文标签。
  String get label => switch (this) {
    CheckinLevel.zero => '未复习',
    CheckinLevel.one => '少量',
    CheckinLevel.two => '达标',
    CheckinLevel.three => '超额',
  };
}

///
/// 单天打卡数据。
///
class CheckinDay {
  /// 创建一天数据。
  ///
  /// @param  DateTime      date        当天日期。
  /// @param  CheckinLevel  level       当天质量分档。
  /// @param  int           reviewCount 当天去重复习单词数。
  const CheckinDay({
    required this.date,
    required this.level,
    required this.reviewCount,
  });

  /// 当天日期。
  final DateTime date;

  /// 当天质量分档。
  final CheckinLevel level;

  /// 当天去重复习的单词数量；点击日期后直接显示这个数字。
  final int reviewCount;
}

///
/// 月历式打卡质量卡片：月份选择器 + 日历色块 + 统计分布条 + 图例。
///
/// 数据来自原生 record 表的真实聚合（选中月份每天去重单词数），
/// 按每日目标分档；查询失败或无记录时显示全"未复习"骨架。
///
class CheckinHeatmapCard extends StatefulWidget {
  /// 创建卡片；默认展示本月。
  ///
  /// @param  int  dailyGoal 每日复习目标，用于把每天的复习量映射到分档。
  /// @param  int  refreshToken 首页复习数据回刷序号，变化即代表需要重新查库。
  const CheckinHeatmapCard({
    required this.dailyGoal,
    required this.refreshToken,
    super.key,
  });

  /// 每日复习目标（来自首页设置）。
  final int dailyGoal;

  ///
  /// 首页传入的回刷序号。
  ///
  /// 生活化解释：日历只在第一次出现时查一次数据库。首页每从复习模块返回一次
  /// 就把这个数字 +1，日历看到号变了才会重查，今天的色块因此能立刻变深。
  ///
  /// @var int
  ///
  final int refreshToken;

  @override
  State<CheckinHeatmapCard> createState() => _CheckinHeatmapCardState();
}

///
/// 管理选中的月份，并异步加载该月的每日复习量。
///
class _CheckinHeatmapCardState extends State<CheckinHeatmapCard> {
  /// 当前选中的月份（统一取该月 1 号）；默认本月。
  late DateTime _month = _firstDayOfMonth(DateTime.now());

  /// 选中月份每天的打卡数据；初始为全"未复习"骨架，色块永不消失。
  List<CheckinDay> _days = const [];

  /// 当前被点击的具体日期；为空表示暂时不展示任何一天的复习数量。
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    // 先铺骨架再异步查询；真实查询毫秒级，加载完成直接刷新。
    _days = _zeroDays(_month);
    _load();
  }

  ///
  /// 首页回刷序号变化时重新查询当前月份的打卡数据。
  ///
  /// 每日目标改变时同样要重查：色块分档是按目标算出来的，目标一变颜色也要跟着变。
  ///
  /// @param  CheckinHeatmapCard  oldWidget 上一次的配置。
  /// @return void
  ///
  @override
  void didUpdateWidget(covariant CheckinHeatmapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 序号和每日目标都没变时，沿用已有色块，不做多余查询。
    if (oldWidget.refreshToken == widget.refreshToken &&
        oldWidget.dailyGoal == widget.dailyGoal) {
      return;
    }
    unawaited(_load());
  }

  ///
  /// 查询选中月份每天的复习单词数（按单词去重）并转为分档。
  ///
  /// @return `Future<void>`
  ///
  Future<void> _load() async {
    try {
      // 捕获发起时的月份，用于丢弃过期结果。
      final month = _month;
      // since 取该月 1 号；原生会把该日期之后的所有天都返回，
      // 下面在 Dart 侧再按"属于该月"过滤一遍。
      final counts = await RecordStore.instance.getDailyReviewCounts(
        since: month,
      );
      // 异步期间卡片可能已移除或切换了月份。
      if (!mounted || _month != month) return;
      // 该月天数（取下月 0 号即本月最后一天）。
      final dayCount = DateTime(month.year, month.month + 1, 0).day;
      setState(() {
        _days = [
          for (var i = 1; i <= dayCount; i++)
            () {
              // 先建立当天日期，避免日期键和数据对象分别重复创建。
              final date = DateTime(month.year, month.month, i);
              // 原生没有返回该日期时，说明当天复习数量为 0。
              final reviewCount = counts[_dateKey(date)] ?? 0;
              return CheckinDay(
                date: date,
                // 颜色档位仍然按照原有每日目标规则计算。
                level: _levelFor(reviewCount, widget.dailyGoal),
                // 同时保留原始数字，供点击日期后就地展示。
                reviewCount: reviewCount,
              );
            }(),
        ];
      });
    } catch (error) {
      // 通道不可用（如单元测试/原生尚未包含新方法）或查询异常：
      // 保持"未复习"骨架不动画，日历色块仍然完整显示。
      debugPrint('读取打卡质量失败：$error');
    }
  }

  ///
  /// 切换月份：先铺该月"未复习"骨架，再立即查询。
  ///
  /// @param  DateTime  month 目标月份（取 1 号）。
  /// @return void
  ///
  void _selectMonth(DateTime month) {
    if (month.year == _month.year && month.month == _month.month) return;
    setState(() {
      _month = month;
      _days = _zeroDays(month);
      // 新月份还没有用户选择，清掉旧月份的日期与数量提示。
      _selectedDate = null;
    });
    _load();
  }

  ///
  /// 选中一个具体日期，让月历只在该日期旁显示当天复习数量。
  ///
  /// @param  DateTime  date 被点击的日期。
  /// @return void
  ///
  void _selectDate(DateTime date) {
    // 日期格每次点击都把展示目标切换到当前日期。
    setState(() => _selectedDate = date);
  }

  ///
  /// 取某月 1 号（把任意日期归一到月份锚点）。
  ///
  /// @param  DateTime  d 任意日期。
  /// @return DateTime 该月 1 号。
  ///
  DateTime _firstDayOfMonth(DateTime d) => DateTime(d.year, d.month);

  ///
  /// 生成某月全"未复习"的骨架数据。
  ///
  /// @param  DateTime  month 月份锚点（1 号）。
  /// @return `List<CheckinDay>` 该月每天都是 zero 档。
  ///
  List<CheckinDay> _zeroDays(DateTime month) {
    // 该月天数。
    final dayCount = DateTime(month.year, month.month + 1, 0).day;
    return [
      for (var i = 1; i <= dayCount; i++)
        CheckinDay(
          date: DateTime(month.year, month.month, i),
          level: CheckinLevel.zero,
          // 骨架阶段尚未查到记录，先按 0 展示；真实查询完成后整体替换。
          reviewCount: 0,
        ),
    ];
  }

  ///
  /// 把某天的复习量映射到分档：相对每日目标的比例。
  ///
  /// - 0 个 → 未复习；
  /// - 不足目标的 60% → 少量；
  /// - 达到 60% 但不足目标 → 达标；
  /// - 达到或超过目标 → 超额。
  ///
  /// @param  int  count 当天去重复习单词数。
  /// @param  int  goal  每日复习目标。
  /// @return CheckinLevel 质量分档。
  ///
  CheckinLevel _levelFor(int count, int goal) {
    // 没复习就是未复习。
    if (count <= 0) return CheckinLevel.zero;
    // 目标为 0 视为无约束：复习了就算超额。
    if (goal <= 0) return CheckinLevel.three;
    // 达到目标即超额档。
    if (count >= goal) return CheckinLevel.three;
    // 超过目标的六成算达标，否则算少量。
    if (count >= goal * 0.6) return CheckinLevel.two;
    return CheckinLevel.one;
  }

  /// 计算连续打卡天数：从"今天"在选中月内倒推非零档。
  ///
  /// 仅当选中月是本月时有意义（连续打卡以今天为终点）；翻看历史月份时
  /// 显示 0。注意：跨月的长连续在本月内只能数到月初，属于已知口径限制。
  int get _streak {
    final now = DateTime.now();
    // 翻看历史月份时今天不在范围内，直接返回 0。
    if (_month.year != now.year || _month.month != now.month) return 0;
    var streak = 0;
    // 从今天（月内最后一天往后不会超过今天）倒推。
    for (final day in _days.reversed) {
      // 超过今天的格子不参与（日历中今天的未来格是灰色占位）。
      if (day.date.isAfter(DateTime(now.year, now.month, now.day))) continue;
      if (day.level == CheckinLevel.zero) break;
      streak++;
    }
    return streak;
  }

  /// 按档位统计数量。
  Map<CheckinLevel, int> get _counts {
    final counts = <CheckinLevel, int>{
      for (final level in CheckinLevel.values) level: 0,
    };
    for (final day in _days) {
      counts[day.level] = counts[day.level]! + 1;
    }
    return counts;
  }

  /// 选中月是否为本月（用于禁用"下个月"按钮）。
  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final counts = _counts;

    // 分布条各段宽度：四档一一对应（未复习/少量/达标/超额）。
    final zeroCount = counts[CheckinLevel.zero]!;
    final oneCount = counts[CheckinLevel.one]!;
    final twoCount = counts[CheckinLevel.two]!;
    final threeCount = counts[CheckinLevel.three]!;

    return MediaQuery.withClampedTextScaling(
      // 日历卡片是紧凑型组件：超大字体下钳制放大上限（与曲线图头部同策略），
      // 防止月份行与图例把固定网格撑出横向溢出；常规 1.0 倍字体不受影响。
      maxScaleFactor: 1.15,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: tokens.card,
          // 描边代替阴影：浅浅一圈分隔线让卡片在灰底上有轮廓。
          border: Border.all(color: tokens.border),
          // 只保留一点点圆角。
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：左"复习质量"、中年月选择器（整行居中）、右连续天数。
          // 两侧 Expanded 平分剩余宽度，中间选择器按自然宽度布局，
          // 因此年月选择器恰好落在整行正中；两侧文字带省略号，
          // 极端窄屏/大字体下收缩截断而不会溢出。
          Row(
            children: [
              // 左：卡片标题（占位可收缩）。
              Expanded(
                child: Text(
                  '复习质量',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tokens.text,
                  ),
                ),
              ),
              // 中：月份选择器（上一个月 ‹ / 年月 / › 下一个月）。
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MonthArrow(
                    icon: TablerIcons.chevronLeft,
                    onTap: () => _selectMonth(
                      _month.month == 1
                          ? DateTime(_month.year - 1, 12)
                          : DateTime(_month.year, _month.month - 1),
                    ),
                    tokens: tokens,
                  ),
                  Flexible(
                    child: Text(
                      '${_month.year}年${_month.month}月',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tokens.text,
                      ),
                    ),
                  ),
                  _MonthArrow(
                    icon: TablerIcons.chevronRight,
                    onTap: _isCurrentMonth
                        ? null
                        : () => _selectMonth(
                            _month.month == 12
                                ? DateTime(_month.year + 1, 1)
                                : DateTime(_month.year, _month.month + 1),
                          ),
                    tokens: tokens,
                  ),
                ],
              ),
              // 右：连续打卡天数（占位可收缩）。
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        TablerIcons.flame,
                        size: 14,
                        color: const Color(0xFFE8590C),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '连续$_streak天',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: tokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 星期表头：固定日~六七列。
          Row(
            children: [
              for (final weekLabel in const [
                '日',
                '一',
                '二',
                '三',
                '四',
                '五',
                '六',
              ])
                Expanded(
                  child: Center(
                    child: Text(
                      weekLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // 日历主体：按周分行，每格一个色块，色块中间是几号。
          _CalendarGrid(
            days: _days,
            selectedDate: _selectedDate,
            onDateTap: _selectDate,
            tokens: tokens,
          ),
          const SizedBox(height: 14),
          // 统计分布条：超额 → 达标 → 少量 → 未复习，从左到右四段。
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  if (threeCount > 0)
                    Expanded(
                      flex: threeCount,
                      child: Container(color: tokens.checkinLevel4),
                    ),
                  if (twoCount > 0)
                    Expanded(
                      flex: twoCount,
                      child: Container(color: tokens.checkinLevel2),
                    ),
                  if (oneCount > 0)
                    Expanded(
                      flex: oneCount,
                      child: Container(color: tokens.checkinLevel1),
                    ),
                  if (zeroCount > 0)
                    Expanded(
                      flex: zeroCount,
                      child: Container(color: tokens.checkinLevel0),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 图例：四个条目与四档色块一一对应；固定宽度，
          // 大字体下可能超宽，允许横向滚动兜底。
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _LegendItem(
                  color: tokens.checkinLevel4,
                  label: '超额',
                  count: threeCount,
                  tokens: tokens,
                ),
                const SizedBox(width: 16),
                _LegendItem(
                  color: tokens.checkinLevel2,
                  label: '达标',
                  count: twoCount,
                  tokens: tokens,
                ),
                const SizedBox(width: 16),
                _LegendItem(
                  color: tokens.checkinLevel1,
                  label: '少量',
                  count: oneCount,
                  tokens: tokens,
                ),
                const SizedBox(width: 16),
                _LegendItem(
                  color: tokens.checkinLevel0,
                  label: '未复习',
                  count: zeroCount,
                  tokens: tokens,
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}

///
/// 日历网格：把一个月的天数据按周排成 6 行 × 7 列。
///
/// 首行前的空位留白；今天之后的日子画成无底色的灰色数字（未来占位）。
///
class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.days,
    required this.selectedDate,
    required this.onDateTap,
    required this.tokens,
  });

  /// 色块边长：接近上一版 16px 色块的紧凑观感，略放大以容纳两位日期数字。
  static const double _cellSize = 20;

  /// 当月每天的数据（1 日..月末，连续无空洞）。
  final List<CheckinDay> days;

  /// 当前选中的日期；其余日期只显示几号，不显示复习数量。
  final DateTime? selectedDate;

  /// 点击具体日期时通知卡片更新选中状态。
  final ValueChanged<DateTime> onDateTap;

  /// 色板令牌。
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    // 没有数据（异常兜底）时整块不渲染，保持卡片其余部分完整。
    if (days.isEmpty) return const SizedBox.shrink();
    // 当月 1 号是星期几：DateTime.weekday 周一=1..周日=7，
    // 日历从周日开始，所以对 7 取余正好落在 0(日)..6(六) 列。
    final firstWeekday = days.first.date.weekday % 7;
    // 今天（去掉时分秒，只留日期），用于把未来的格子灰掉。
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 组装一周一行的小组：先补 firstWeekday 个空位，再逐天入列。
    // 空位用 null、日期用 CheckinDay，所以元素类型是 Object?。
    final cells = <Object?>[
      // 月首前的空白格。
      for (var i = 0; i < firstWeekday; i++) null,
      // 每天一个格子。
      for (final day in days) day,
    ];
    // 行数 = 向上取整（格子总数 / 7）。
    final rowCount = (cells.length + 6) ~/ 7;

    return Column(
      children: [
        for (var row = 0; row < rowCount; row++) ...[
          if (row > 0) const SizedBox(height: 6),
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  // 色块固定小尺寸、在所在列内居中；行高由色块决定，
                  // 整体接近上一版横排色块的紧凑密度。
                  child: Center(
                    child: _buildCell(cells, row * 7 + col, today),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  ///
  /// 渲染单个日历格。
  ///
  /// @param  `List<Object?>`  cells  含空位的格子序列。
  /// @param  int               index  本格在序列中的下标。
  /// @param  DateTime          today  今天（零点）。
  /// @return Widget
  ///
  Widget _buildCell(List<Object?> cells, int index, DateTime today) {
    // 越界或月首空位：透明占位，撑住网格结构。
    if (index >= cells.length || cells[index] == null) {
      return const SizedBox.shrink();
    }
    // 该格对应的当天数据。
    final day = cells[index] as CheckinDay;
    // 今天之后的未来日子：只画灰色数字，不铺复习色。
    final isFuture = day.date.isAfter(today);
    // 年、月、日同时相同才视为选中，避免跨月份误命中相同日号。
    final isSelected =
        selectedDate?.year == day.date.year &&
        selectedDate?.month == day.date.month &&
        selectedDate?.day == day.date.day;
    // 日期键用于稳定定位每一个具体日期及其点击后出现的数量。
    final dateKey = _dateKey(day.date);

    // 先沿用日期原有样式，再统一包进可点击的一列网格中。
    final Widget dateNumber;

    if (isFuture) {
      // 未来占位：极淡数字，无底色。
      dateNumber = SizedBox(
        width: _cellSize,
        child: Center(
          child: Text(
            '${day.date.day}',
            style: TextStyle(fontSize: 11, color: tokens.listDateEmpty),
          ),
        ),
      );
    } else {
      // 已过去的日子：按分档铺底色，固定小方块正中显示几号。
      dateNumber = SizedBox(
        width: _cellSize,
        height: _cellSize,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: day.level.color(tokens),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Center(
            child: Text(
              '${day.date.day}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                // 深蓝底用白字，浅蓝/灰底用主文字色，保证可读。
                color: day.level == CheckinLevel.three
                    ? Colors.white
                    : day.level == CheckinLevel.zero
                    ? tokens.textSecondary
                    : tokens.text,
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      // 读屏软件会把日期格识别成可点击按钮，并读出完整日期。
      button: true,
      label: '${day.date.year}年${day.date.month}月${day.date.day}日',
      // 选中后把复习数量加入读屏值，视觉上仍只额外显示一个数字。
      value: isSelected ? '${day.reviewCount}' : null,
      child: GestureDetector(
        key: Key('checkin-day-$dateKey'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onDateTap(day.date),
        child: SizedBox(
          // 占满日历列宽，数字出现时不会改变网格的行列位置。
          height: _cellSize,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              dateNumber,
              if (isSelected) ...[
                const SizedBox(width: 3),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${day.reviewCount}',
                      key: Key('checkin-count-$dateKey'),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: tokens.text,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

///
/// 月份切换箭头按钮。
///
class _MonthArrow extends StatelessWidget {
  const _MonthArrow({required this.icon, required this.onTap, required this.tokens});

  /// Tabler 箭头图标。
  final IconData icon;

  /// 点击回调；null 表示禁用（如本月不能再往后翻）。
  final VoidCallback? onTap;

  /// 色板令牌。
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      // opaque 让整块区域可点（禁用时 onTap 为 null 自然不响应）。
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Icon(
          icon,
          size: 18,
          // 禁用时降到极淡灰，可用时用次要文字色。
          color: onTap == null ? tokens.listDateEmpty : tokens.textSecondary,
        ),
      ),
    );
  }
}

///
/// 图例项：色点 + 标签 + 数量。
///
class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    required this.count,
    required this.tokens,
  });

  final Color color;
  final String label;
  final int count;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: tokens.textSecondary),
        ),
        const SizedBox(width: 3),
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: tokens.text,
          ),
        ),
      ],
    );
  }
}

///
/// 日期键：与原生 record 表 created_date 完全一致的 'yyyy-MM-dd'。
///
/// @param  DateTime  d
/// @return String
///
String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
