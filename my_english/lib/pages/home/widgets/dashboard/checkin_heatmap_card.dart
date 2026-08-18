// material.dart 提供布局与文字组件。
import 'package:flutter/material.dart';
// tabler_icons_plus 提供火焰图标。
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

// 引入设计稿色板令牌。
import '../../../../common/theme.dart';

///
/// 打卡质量分档：对应原型 lvl-0 ~ lvl-4。
///
enum CheckinLevel {
  /// 未复习。
  zero,

  /// 少量/未达标。
  one,

  /// 刚好达标。
  two,

  /// 达标偏多。
  three,

  /// 超额完成。
  four,
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
    CheckinLevel.three => tokens.checkinLevel3,
    CheckinLevel.four => tokens.checkinLevel4,
  };

  /// 中文标签。
  String get label => switch (this) {
    CheckinLevel.zero => '未练',
    CheckinLevel.one => '少量',
    CheckinLevel.two => '达标',
    CheckinLevel.three => '达标',
    CheckinLevel.four => '超额',
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
/// 30 天打卡质量卡片：色块条 + 统计分布条 + 图例。
///
/// 数据目前为假数据，后续替换为真实 record 聚合查询。
///
class CheckinHeatmapCard extends StatelessWidget {
  /// 创建卡片；数据由内部假数据提供。
  const CheckinHeatmapCard({super.key});

  /// 生成 30 天假数据。
  List<CheckinDay> get _days {
    final today = DateTime.now();
    final seed = 30 * 3 + 7;
    final random = _SimpleRandom(seed);
    final levels = CheckinLevel.values;
    // 让分布偏向中高档，模拟连续学习状态。
    final weights = <CheckinLevel, int>{
      CheckinLevel.zero: 2,
      CheckinLevel.one: 3,
      CheckinLevel.two: 3,
      CheckinLevel.three: 2,
      CheckinLevel.four: 3,
    };
    final weighted = <CheckinLevel>[];
    for (final level in levels) {
      for (var i = 0; i < weights[level]!; i++) {
        weighted.add(level);
      }
    }
    return List.generate(30, (index) {
      final date = today.subtract(Duration(days: 29 - index));
      final level = weighted[random.nextInt(weighted.length)];
      return CheckinDay(date: date, level: level);
    });
  }

  /// 计算连续打卡天数（从今天倒推非零档）。
  int get _streak {
    final days = _days.reversed;
    var streak = 0;
    for (final day in days) {
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

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final days = _days;
    final counts = _counts;
    final total = days.length;

    // 分布条各段宽度（按 0/1/2-3/4 分组展示，对齐原型「未练/少量/达标/超额」）。
    final zeroCount = counts[CheckinLevel.zero]!;
    final oneCount = counts[CheckinLevel.one]!;
    final twoThreeCount =
        counts[CheckinLevel.two]! + counts[CheckinLevel.three]!;
    final fourCount = counts[CheckinLevel.four]!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: tokens.cardShadow,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：标题 + 连续天数。标题包 Expanded 弹性收缩，
          // 窄屏大字体下自动省略号截断，避免整行横向溢出。
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '近30天打卡质量',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: tokens.textSecondary,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    TablerIcons.flame,
                    size: 14,
                    color: const Color(0xFFE8590C),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '连续 $_streak 天',
                    style: TextStyle(
                      fontSize: 13,
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 30 个色块横排（可横向滚动）。
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < days.length; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: days[i].level.color(tokens),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 统计分布条。
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  if (fourCount > 0)
                    Expanded(
                      flex: fourCount,
                      child: Container(color: tokens.checkinLevel4),
                    ),
                  if (twoThreeCount > 0)
                    Expanded(
                      flex: twoThreeCount,
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
          // 图例：四个条目固有宽度，大字体下可能超宽，允许横向滚动兜底。
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _LegendItem(
                  color: tokens.checkinLevel4,
                  label: '超额',
                  count: fourCount,
                  tokens: tokens,
                ),
                const SizedBox(width: 16),
                _LegendItem(
                  color: tokens.checkinLevel2,
                  label: '达标',
                  count: twoThreeCount,
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
                  label: '未练',
                  count: zeroCount,
                  tokens: tokens,
                ),
              ],
            ),
          ),
          // 避免 unused 警告。
          Text('$total', style: const TextStyle(fontSize: 0)),
        ],
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
/// 极简线性同余伪随机数生成器，避免依赖 dart:math.Random 的种子行为差异。
///
class _SimpleRandom {
  _SimpleRandom(this._state);

  int _state;

  int nextInt(int max) {
    // 线性同余：经典参数。
    _state = (1103515245 * _state + 12345) & 0x7FFFFFFF;
    return _state % max;
  }
}
