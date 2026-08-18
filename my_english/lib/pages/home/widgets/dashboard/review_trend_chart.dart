// material.dart 提供布局与手势组件，类似小程序内置的 view / gesture。
import 'package:flutter/material.dart';
// dart:async 提供定时器 Timer，用于模拟后台异步加载数据。
import 'dart:async';

// 引入设计稿色板令牌。
import '../../../../common/theme.dart';
// 引入可复用的曲线图组件（纯展示，不绑定业务）。
import 'trend_chart.dart';
// 引入默写记录 Store：按天/按月的复习量聚合查询都走这里。
import '../../../../store/record.dart';

///
/// 趋势图时间范围标签；对应原型 chart-tabs。
///
enum TrendRange {
  /// 近 7 天。
  week,

  /// 近 30 天。
  month,

  /// 近半年（最近七个月）。
  halfYear,

  /// 近一年。
  year,

  /// 全部历史（首条记录月份到本月，按月汇总）。
  all,
}

///
/// 为时间范围补充界面文字。
///
extension TrendRangeLabel on TrendRange {
  /// tab 显示文字。
  String get label => switch (this) {
    TrendRange.week => '7天',
    TrendRange.month => '30天',
    TrendRange.halfYear => '半年',
    TrendRange.year => '一年',
    TrendRange.all => '全部',
  };
}

///
/// 顶部仪表盘第一块：时间范围 tab + 平滑趋势曲线。
///
/// 数据来自原生 record 表的真实聚合（按天或按月去重单词数）：
/// 进入页面时先渲染"空数据"（全 0 的水平直线），异步查询完成后由
/// [TrendChart] 内部把节点平滑滑动到目标位置。
///
class ReviewTrendChart extends StatefulWidget {
  /// 创建趋势图；数据由内部异步加载。
  const ReviewTrendChart({super.key});

  @override
  State<ReviewTrendChart> createState() => _ReviewTrendChartState();
}

///
/// 管理当前选中的时间范围，并异步加载对应粒度的真实统计。
///
class _ReviewTrendChartState extends State<ReviewTrendChart> {
  /// 安全边界线：与仪表盘 ListView 的水平内边距一致（问候语、汉堡菜单
  /// 距屏幕边缘的距离）。节点与文字排列在此边界内，曲线、渐变、
  /// 分割线则突破边界直达屏幕边缘。
  static const double _edgeInset = 20;

  /// 每个范围固定 7 个节点：首尾两个端点 + 中间 5 个均分节点。
  static const int _nodeCount = 7;

  /// 进入页面后延迟加载数据的时长：保证"先看到空数据直线，
  /// 再看到节点滑上来"的过渡节奏。
  static const Duration _initialDelay = Duration(milliseconds: 600);

  /// 当前选中的范围，默认 7 天。
  TrendRange _range = TrendRange.week;

  /// 当前画面数据：初始为全 0 空数据（贴底水平直线），加载完成后替换。
  List<TrendDataPoint> _points = const [];

  /// 初次延迟加载定时器；页面销毁时取消，防止泄漏与测试报错。
  Timer? _loadTimer;

  @override
  void initState() {
    super.initState();
    // 先用当前范围的空数据铺出节点骨架（label 已就绪，value 全 0）。
    _points = _flatPoints(_range);
    // 模拟后台异步查询：600ms 后才发起真实聚合，期间曲线是贴底直线，
    // 最右侧（今天）节点默认选中并显示 0。
    _loadTimer = Timer(_initialDelay, _load);
  }

  @override
  void dispose() {
    // 页面销毁时取消未完成的加载定时器。
    _loadTimer?.cancel();
    super.dispose();
  }

  /// 切换范围：先立刻切到新范围的空数据直线，再马上发起查询。
  void _selectRange(TrendRange range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      // 先展示该档的空数据骨架，数据到达后节点再滑动上来。
      _points = _flatPoints(range);
    });
    // 查询是毫秒级，切换后立即加载，不额外加延迟。
    _load();
  }

  ///
  /// 发起真实聚合查询并刷新曲线。
  ///
  /// 查询期间用户可能又切了档：用发起时捕获的范围做过期守卫，
  /// 旧结果回来直接丢弃，避免覆盖新档数据。
  ///
  /// @return `Future<void>`
  ///
  Future<void> _load() async {
    // 捕获发起时的范围，用于丢弃过期结果。
    final range = _range;
    try {
      // 按范围查真实数据（原生 SQLite 聚合，毫秒级）。
      final points = await _loadPoints(range);
      // 异步期间页面可能已关闭或切换了时间档。
      if (!mounted || _range != range) return;
      // 更新曲线，TrendChart 内部会播放匀速滑动过渡。
      setState(() => _points = points);
    } catch (error) {
      // 通道不可用（如单元测试）或查询异常：保持空数据直线，不影响首页。
      debugPrint('读取复习趋势失败：$error');
    }
  }

  ///
  /// 按范围查询真实数据并组装成曲线节点。
  ///
  /// - 7天 / 30天：日粒度，走 [RecordStore.getDailyReviewCounts]；
  /// - 半年 / 一年 / 全部：月粒度，走 [RecordStore.getMonthlyReviewCounts]
  ///   （按月去重才是正确口径，不能把每日去重数相加）。
  ///   「全部」不限起始月份，用首条与末条记录所在月份作为首尾端点均分节点；
  ///   一年与全部跨度大，label 统一用「XX年X月」格式。
  ///
  /// @param  TrendRange  range 时间范围。
  /// @return `Future<List<TrendDataPoint>>` 7 个节点的真实数据。
  ///
  Future<List<TrendDataPoint>> _loadPoints(TrendRange range) async {
    final today = DateTime.now();
    final store = RecordStore.instance;

    switch (range) {
      case TrendRange.week:
        // 7 天：今天往前数 6 天到今天，每天一个节点。
        final since = today.subtract(const Duration(days: _nodeCount - 1));
        final counts = await store.getDailyReviewCounts(since: since);
        return [
          for (var i = 0; i < _nodeCount; i++)
            () {
              final d = today.subtract(Duration(days: _nodeCount - 1 - i));
              return TrendDataPoint(
                label: _dayLabel(today, d),
                value: (counts[_dateKey(d)] ?? 0).toDouble(),
              );
            }(),
        ];

      case TrendRange.month:
        // 30 天：跨度 30 天，7 个节点按天数均分（含首尾端点）。
        final counts = await store.getDailyReviewCounts(
          since: today.subtract(const Duration(days: 30)),
        );
        return [
          for (var i = 0; i < _nodeCount; i++)
            () {
              final dayOffset =
                  ((_nodeCount - 1 - i) * 30 / (_nodeCount - 1)).round();
              final d = today.subtract(Duration(days: dayOffset));
              return TrendDataPoint(
                label: _dayLabel(today, d),
                value: (counts[_dateKey(d)] ?? 0).toDouble(),
              );
            }(),
        ];

      case TrendRange.halfYear:
        // 半年：最近七个月，按月均分节点（本月往前数 6 个月到本月）。
        final counts = await store.getMonthlyReviewCounts(
          since: _addMonths(today, -(_nodeCount - 1)),
        );
        // 跨年时整段 label 统一带年份（XX年X月），避免"12月/1月"分不清是哪年。
        final withYear =
            _addMonths(today, -(_nodeCount - 1)).year != today.year;
        return [
          for (var i = 0; i < _nodeCount; i++)
            () {
              final d = _addMonths(today, -(_nodeCount - 1 - i));
              return TrendDataPoint(
                label: _monthLabel(d, withYear: withYear),
                value: (counts[_monthKey(d)] ?? 0).toDouble(),
              );
            }(),
        ];

      case TrendRange.year:
        // 一年：本月与去年本月为首尾，中间月份均分；12 个月跨度必跨年。
        final counts = await store.getMonthlyReviewCounts(
          since: _addMonths(today, -12),
        );
        return [
          for (var i = 0; i < _nodeCount; i++)
            () {
              final monthOffset = -12 * (_nodeCount - 1 - i) ~/ (_nodeCount - 1);
              final d = _addMonths(today, monthOffset);
              return TrendDataPoint(
                label: _monthLabel(d, withYear: true),
                value: (counts[_monthKey(d)] ?? 0).toDouble(),
              );
            }(),
        ];

      case TrendRange.all:
        // 全部：按月聚合、不限起始月份；原生按月份升序返回，Map 保持
        // 插入顺序，首个键即首条记录所在月份、末个键即最近记录所在月份。
        final counts = await store.getMonthlyReviewCounts();
        // 一条记录都没有：回退为「最近十二个月」的空数据骨架。
        if (counts.isEmpty) return _flatPoints(range);
        // 首尾端点 = 第一条与最后一条记录所在的月份。
        final first = _parseMonth(counts.keys.first);
        final last = _parseMonth(counts.keys.last);
        // 两个月份之间的总月数（0 表示只在同一个月内有记录）。
        final totalMonths =
            (last.year - first.year) * 12 + (last.month - first.month);
        return [
          for (var i = 0; i < _nodeCount; i++)
            () {
              final d = _addMonths(
                first,
                (totalMonths * i / (_nodeCount - 1)).round(),
              );
              return TrendDataPoint(
                // 全部跨度大且通常跨年：统一用「XX年X月」格式。
                label: _monthLabel(d, withYear: true),
                value: (counts[_monthKey(d)] ?? 0).toDouble(),
              );
            }(),
        ];
    }
  }

  ///
  /// 生成某个范围的空数据骨架：label 按该档粒度排好，value 全 0。
  ///
  /// 「全部」在拿到真实首尾记录前无法确定节点日期，先用「去年到今天」
  /// 的默认跨度占位；查询回来后会被真实节点替换。
  ///
  /// @param  TrendRange  range 时间范围。
  /// @return `List<TrendDataPoint>` 全 0 的 7 个节点。
  ///
  List<TrendDataPoint> _flatPoints(TrendRange range) {
    final today = DateTime.now();
    final labels = <String>[];
    switch (range) {
      case TrendRange.week:
        for (var i = 0; i < _nodeCount; i++) {
          final d = today.subtract(Duration(days: _nodeCount - 1 - i));
          labels.add(_dayLabel(today, d));
        }
      case TrendRange.month:
        for (var i = 0; i < _nodeCount; i++) {
          final dayOffset =
              ((_nodeCount - 1 - i) * 30 / (_nodeCount - 1)).round();
          final d = today.subtract(Duration(days: dayOffset));
          labels.add(_dayLabel(today, d));
        }
      case TrendRange.halfYear:
        final withYear =
            _addMonths(today, -(_nodeCount - 1)).year != today.year;
        for (var i = 0; i < _nodeCount; i++) {
          final d = _addMonths(today, -(_nodeCount - 1 - i));
          labels.add(_monthLabel(d, withYear: withYear));
        }
      case TrendRange.year:
        for (var i = 0; i < _nodeCount; i++) {
          final monthOffset = -12 * (_nodeCount - 1 - i) ~/ (_nodeCount - 1);
          final d = _addMonths(today, monthOffset);
          labels.add(_monthLabel(d, withYear: true));
        }
      case TrendRange.all:
        // 全部（无记录时）：按「最近十二个月」铺月度骨架占位，与一年档一致。
        for (var i = 0; i < _nodeCount; i++) {
          final monthOffset = -12 * (_nodeCount - 1 - i) ~/ (_nodeCount - 1);
          final d = _addMonths(today, monthOffset);
          labels.add(_monthLabel(d, withYear: true));
        }
    }
    // value 全 0：一条贴着分割线的水平直线。
    return [
      for (final label in labels) TrendDataPoint(label: label, value: 0),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 头部行：左侧"复习量"标题徽章 + 右侧时间选择器。
        // 字号约定：时间选择器 13（与首页"已收录 xx 个单词"副标题一致），
        // 复习量徽章 11（比它小 2px）。五个 tab 直接平铺，不进滚动容器、
        // 也不套 FittedBox 之类的整体缩放，保证字号所见即所得。
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _edgeInset),
          // 仅在系统超大字体（无障碍）时钳制放大上限，防止五个 tab 撑爆整行；
          // 常规字号（1.0 倍）下钳制完全不生效，不存在任何缩放。
          // 1.15 的上限经 320px + 2 倍字体用例验证仍有约 10px 余量。
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.15,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTokens.accent,
                    // 999 的圆角半径远超文字高度，视觉上就是完整胶囊圆角。
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '复习量',
                    style: TextStyle(
                      // 比时间选择器小 2px。
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                // 弹性占位：把时间选择器推到右边缘。
                const Spacer(),
                // 时间选择器：五个 tab 一次性全部展示，无滚动、无缩放。
                Row(
                  children: [
                    for (final range in TrendRange.values) ...[
                      if (range != TrendRange.values.first)
                        const SizedBox(width: 12),
                      _RangeTab(
                        label: range.label,
                        isActive: range == _range,
                        onTap: () => _selectRange(range),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        // 曲线图：直接把数据交给可复用组件渲染；组件内部处理坐标、渐变、
        // 选中交互与数据过渡动画。edgeInset 告诉组件安全边界在哪，
        // 曲线/渐变/分割线会突破边界画到屏幕边缘，节点与文字留在边界内。
        TrendChart(data: _points, edgeInset: _edgeInset),
      ],
    );
  }
}

///
/// 把日期格式化为日粒度横轴标签。
///
/// 同年显示 "M.DD"（如 8.12，自带月份，跨月不混淆）；
/// 跨年（日期不在今年）补两位年份前缀显示 "YY.M.DD"（如 25.12.28）。
///
/// @param  DateTime  now  今天（用于判断跨年）
/// @param  DateTime  d    要格式化的日期
/// @return String
///
String _dayLabel(DateTime now, DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  return d.year == now.year
      ? '${d.month}.$day'
      : '${d.year % 100}.${d.month}.$day';
}

///
/// 把日期格式化为月粒度横轴标签。
///
/// 未跨年的范围显示 "M月"（如 8月）；跨年的范围（一年/全部）统一显示
/// "XX年X月"（如 25年8月），长跨度下每个节点都能看清年份。
///
/// @param  DateTime  d          要格式化的日期
/// @param  bool      withYear   是否带年份（一年/全部档恒为 true）
/// @return String
///
String _monthLabel(DateTime d, {required bool withYear}) =>
    withYear ? '${d.year % 100}年${d.month}月' : '${d.month}月';

///
/// 解析原生月度聚合键 'yyyy-MM' 为该月 1 号的 DateTime。
///
/// @param  String  ym 形如 '2026-08' 的月份键
/// @return DateTime 该月 1 号
///
DateTime _parseMonth(String ym) {
  // 按 '-' 拆成年与月两段。
  final parts = ym.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]));
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

///
/// 月份键：与原生月度聚合一致的 'yyyy-MM'。
///
/// @param  DateTime  d
/// @return String
///
String _monthKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}';

///
/// 在给定日期上增减月份，自动处理跨年与月末溢出（如 1月31日 -1 月 → 2月末）。
///
DateTime _addMonths(DateTime d, int delta) {
  var m = d.month + delta;
  var y = d.year;
  // 月份可能越界，循环进位/借位到合法区间 1..12。
  while (m <= 0) {
    m += 12;
    y -= 1;
  }
  while (m > 12) {
    m -= 12;
    y += 1;
  }
  // 目标月可能没有原日期（如 31 号落到只有 28/30 天的月），钳制到月末。
  final lastDay = DateTime(y, m + 1, 0).day;
  final day = d.day > lastDay ? lastDay : d.day;
  return DateTime(y, m, day);
}

///
/// 单个范围 tab；选中时底部出现主色下划线。
///
class _RangeTab extends StatelessWidget {
  const _RangeTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 时间选择器字号 13，与首页"已收录 xx 个单词"副标题一致；
            // 外层已无任何缩放容器，字号所见即所得。
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? tokens.text : tokens.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            // 选中时的主色短下划线。
            Container(
              width: 24,
              height: 3,
              decoration: BoxDecoration(
                color: isActive ? AppTokens.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
