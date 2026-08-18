// material.dart 提供布局、文字与异步状态组件。
import 'package:flutter/material.dart';
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
  const CheckinDay({required this.date, required this.level});

  /// 当天日期。
  final DateTime date;

  /// 当天质量分档。
  final CheckinLevel level;
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
  const CheckinHeatmapCard({required this.dailyGoal, super.key});

  /// 每日复习目标（来自首页设置）。
  final int dailyGoal;

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

  @override
  void initState() {
    super.initState();
    // 先铺骨架再异步查询；真实查询毫秒级，加载完成直接刷新。
    _days = _zeroDays(_month);
    _load();
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
            CheckinDay(
              date: DateTime(month.year, month.month, i),
              level: _levelFor(
                counts[_dateKey(DateTime(month.year, month.month, i))] ?? 0,
                widget.dailyGoal,
              ),
            ),
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
    });
    _load();
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
          _CalendarGrid(days: _days, tokens: tokens),
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
  const _CalendarGrid({required this.days, required this.tokens});

  /// 色块边长：接近上一版 16px 色块的紧凑观感，略放大以容纳两位日期数字。
  static const double _cellSize = 20;

  /// 当月每天的数据（1 日..月末，连续无空洞）。
  final List<CheckinDay> days;

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

    if (isFuture) {
      // 未来占位：极淡数字，无底色。
      return Text(
        '${day.date.day}',
        style: TextStyle(fontSize: 11, color: tokens.listDateEmpty),
      );
    }

    // 已过去的日子：按分档铺底色，固定小方块正中显示几号。
    return SizedBox(
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
