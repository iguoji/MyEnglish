// dart:math 提供数学函数，用于计算贝塞尔控制点与最大值归一化。
import 'dart:math' as math;
// material.dart 提供画布、手势与布局组件。
import 'package:flutter/material.dart';

// 引入设计稿色板令牌。
import '../../../../common/theme.dart';

///
/// 趋势图时间范围标签；对应原型 chart-tabs。
///
enum TrendRange {
  /// 近 7 天。
  week,

  /// 近 30 天。
  month,

  /// 近半年。
  halfYear,

  /// 近一年。
  year,

  /// 全部历史。
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

  /// 对应的天数；all 用 0 表示由调用方决定。
  int get days => switch (this) {
    TrendRange.week => 7,
    TrendRange.month => 30,
    TrendRange.halfYear => 182,
    TrendRange.year => 365,
    TrendRange.all => 0,
  };
}

///
/// 单个数据点：某天的复习单词数（去重）。
///
class TrendPoint {
  /// 创建一个数据点。
  const TrendPoint({required this.date, required this.count});

  /// 当天日期。
  final DateTime date;

  /// 当天去重后的复习单词数。
  final int count;
}

///
/// 顶部仪表盘第一块：时间范围 tab + 平滑趋势曲线。
///
/// 数据目前为假数据，后续接入真实 record 查询时只需替换 [_fakePoints]。
///
class ReviewTrendChart extends StatefulWidget {
  /// 创建趋势图；数据由内部假数据提供，后续替换为真实数据源。
  const ReviewTrendChart({super.key});

  @override
  State<ReviewTrendChart> createState() => _ReviewTrendChartState();
}

///
/// 管理当前选中的时间范围，并据此生成对应粒度的假数据。
///
class _ReviewTrendChartState extends State<ReviewTrendChart> {
  /// 当前选中的范围，默认 7 天。
  TrendRange _range = TrendRange.week;

  /// 切换范围时刷新曲线。
  void _selectRange(TrendRange range) {
    if (range == _range) return;
    setState(() => _range = range);
  }

  /// 按当前范围生成假数据；后续替换为真实查询结果。
  List<TrendPoint> get _points {
    final today = DateTime.now();
    final days = _range.days == 0 ? 30 : _range.days;
    // 用固定伪随机种子生成稳定的假数据，避免每次 build 都变。
    final seed = days * 7 + 13;
    final random = math.Random(seed);
    return List.generate(days, (index) {
      final date = today.subtract(Duration(days: days - 1 - index));
      // 让数据有一定的波动但整体上升。
      final base = (index / days) * 80 + 20;
      final noise = random.nextDouble() * 40;
      return TrendPoint(date: date, count: (base + noise).round().clamp(0, 200));
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final points = _points;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 时间范围 tabs：窄屏大字体下总宽可能超出，允许横向滚动兜底。
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final range in TrendRange.values) ...[
                if (range != TrendRange.values.first) const SizedBox(width: 16),
                _RangeTab(
                  label: range.label,
                  isActive: range == _range,
                  onTap: () => _selectRange(range),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        // 曲线图：横跨全宽（含左右负边距，对齐原型 full-width-chart）。
        SizedBox(
          height: 130,
          child: _TrendCurve(points: points, color: AppTokens.accent, bg: tokens.page),
        ),
      ],
    );
  }
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
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? tokens.text : tokens.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
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

///
/// 用 CustomPaint 绘制平滑曲线 + 渐变填充 + 数据点。
///
class _TrendCurve extends StatelessWidget {
  const _TrendCurve({required this.points, required this.color, required this.bg});

  final List<TrendPoint> points;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TrendCurvePainter(points: points, color: color, bg: bg),
    );
  }
}

///
/// 曲线画笔：底部基线 + 渐变面积 + 平滑路径 + 数据点 + 最新值标签。
///
class _TrendCurvePainter extends CustomPainter {
  _TrendCurvePainter({
    required this.points,
    required this.color,
    required this.bg,
  });

  final List<TrendPoint> points;
  final Color color;
  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final w = size.width;
    final h = size.height;
    // 底部留 16 给日期标签。
    final bottom = h - 16;
    // 顶部留 20 给最新值标签。
    final top = 20.0;

    final maxCount = points
        .map((p) => p.count)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();
    final yMax = math.max(maxCount, 1.0);

    // 计算 x 坐标：等分到画布宽度。
    final xStep = points.length == 1 ? 0.0 : w / (points.length - 1);
    final xs = List<double>.generate(
      points.length,
      (i) => points.length == 1 ? w / 2 : i * xStep,
    );
    // 计算 y 坐标：count 越大越靠上。
    final ys = List<double>.generate(
      points.length,
      (i) => bottom - (points[i].count / yMax) * (bottom - top),
    );

    // 平滑路径：用相邻点中点作为控制点生成三次贝塞尔。
    final linePath = Path()..moveTo(xs.first, ys.first);
    for (var i = 1; i < points.length; i++) {
      final prevX = xs[i - 1];
      final prevY = ys[i - 1];
      final curX = xs[i];
      final curY = ys[i];
      final midX = (prevX + curX) / 2;
      linePath.cubicTo(midX, prevY, midX, curY, curX, curY);
    }

    // 面积路径：从曲线闭合到底部。
    final areaPath = Path.from(linePath)
      ..lineTo(xs.last, bottom)
      ..lineTo(xs.first, bottom)
      ..close();

    // 渐变填充。
    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, top, w, bottom - top));
    canvas.drawPath(areaPath, areaPaint);

    // 底部基线。
    final basePaint = Paint()
      ..color = const Color(0xFFEBEBEB)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, bottom), Offset(w, bottom), basePaint);

    // 曲线本身。
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);

    // 数据点。
    final dotPaint = Paint()..color = color;
    for (var i = 0; i < points.length; i++) {
      // 中间点小圆，最后一个点用更大圆 + 中心镂空。
      if (i == points.length - 1) {
        canvas.drawCircle(Offset(xs[i], ys[i]), 4.5, dotPaint);
        canvas.drawCircle(Offset(xs[i], ys[i]), 2, Paint()..color = bg);
      } else {
        canvas.drawCircle(Offset(xs[i], ys[i]), 3, dotPaint);
      }
    }

    // 日期标签：首、中、尾。
    final labelPaint = Paint();
    final labelStyle = TextStyle(fontSize: 10, color: const Color(0xFFA0A0A0));
    void drawLabel(String text, double x, TextAlign align) {
      final span = TextSpan(text: text, style: labelStyle);
      final painter = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
        textAlign: align,
      )..layout();
      double dx;
      switch (align) {
        case TextAlign.left:
          dx = x;
          break;
        case TextAlign.right:
          dx = x - painter.width;
          break;
        default:
          dx = x - painter.width / 2;
      }
      painter.paint(canvas, Offset(dx, bottom + 4));
      // 避免 unused 警告。
      labelPaint.toString();
    }

    drawLabel(_formatDate(points.first.date), 0, TextAlign.left);
    if (points.length > 2) {
      final mid = points.length ~/ 2;
      drawLabel(_formatDate(points[mid].date), xs[mid], TextAlign.center);
    }
    drawLabel(_formatDate(points.last.date), w, TextAlign.right);

    // 右上角最新值标签。
    final valueSpan = TextSpan(
      text: points.last.count.toString(),
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: color,
      ),
    );
    final valuePainter = TextPainter(
      text: valueSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    )..layout();
    valuePainter.paint(canvas, Offset(w - valuePainter.width, 2));
  }

  /// 格式化日期为 M.D。
  String _formatDate(DateTime date) {
    return '${date.month}.${date.day}';
  }

  @override
  bool shouldRepaint(covariant _TrendCurvePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.color != color ||
        oldDelegate.bg != bg;
  }
}
