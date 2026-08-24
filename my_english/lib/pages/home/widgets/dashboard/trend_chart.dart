// dart:math 提供数学函数，用于贝塞尔控制点计算、数值归一化与命中区域判断。
import 'dart:math' as math;
// material.dart 提供画布、手势与布局组件。
import 'package:flutter/material.dart';

// 引入设计稿色板令牌；曲线主色与背景色都从这里读取，自动适配浅色/深色。
import '../../../../common/theme.dart';

///
/// 曲线图单个数据点。
///
/// 把"横轴文字"与"纵轴数值"打包成一个对象：外部只要传入形如
/// [{label:"8.12", value:0}, {label:"8.13", value:10}] 的数据即可渲染，
/// 组件本身不关心数据来自几天、几个月，还是临时造的假数据。
///
class TrendDataPoint {
  /// 创建一个数据点。
  const TrendDataPoint({required this.label, required this.value});

  /// 横轴下方显示的文字，例如日期 "8.12"。
  final String label;

  /// 节点的纵轴数值；数值越大曲线越高。
  final double value;
}

///
/// 可复用的趋势曲线组件（纯展示 + 选中交互 + 数据过渡动画）。
///
/// 布局约定（对应设计稿的"安全边界线"概念）：
/// - [edgeInset] 是页面内容距屏幕左右边缘的距离（与问候语、汉堡菜单一致）；
/// - 曲线、曲线下的渐变色、底部分割线三项会突破边界一直画到屏幕边缘；
/// - 节点圆点、选中值数字、横轴 label 则排列在安全边界之内。
///
/// 纵坐标映射规则（对应 CSS 的 bottom 百分比概念）：
/// - 数值相对最小时，节点位于距分割线 30%（约三分之一）处，
///   保证最低点下方仍有空间展示渐变色；
/// - 数值相对最大时，节点位于顶部（bottom 100%）；
/// - 中间数值按线性插值。
///
/// 交互与动画：
/// - 默认选中最后一个节点，在其上方显示数值；点击其他节点可切换查看；
/// - 数据变化时（异步加载完成、切换时间档），各节点以相同速度从旧位置
///   匀速滑到新位置：落差小的先到，落差大的后到，不存在同时到达的变速感；
/// - 所有数值相等（如刚进入页面的空数据）时呈一条贴着底部的水平直线。
///
class TrendChart extends StatefulWidget {
  /// 创建曲线图；传入非空 data 即可渲染。
  const TrendChart({
    required this.data,
    this.color,
    this.height = 140,
    this.edgeInset = 0,
    this.duration = const Duration(milliseconds: 600),
    super.key,
  });

  /// 要绘制的数据点列表；每个点包含横轴文字 label 与纵轴数值 value。
  final List<TrendDataPoint> data;

  /// 曲线主色；不传则使用品牌蓝 [AppTokens.accent]。
  final Color? color;

  /// 曲线图整体高度（含底部日期标签的预留区）。
  final double height;

  /// 安全边界：节点、数值与 label 排列在距左右边缘该距离的范围内；
  /// 曲线、渐变、分割线不受此限制，会一直画到画布两端。
  final double edgeInset;

  /// 数据过渡总时长：对应"落差最大的节点"从旧位置滑到新位置的时间。
  /// 所有节点以相同速度移动，落差小的会提前到达（类似多段匀速的 transition）。
  final Duration duration;

  @override
  State<TrendChart> createState() => _TrendChartState();
}

///
/// 管理选中节点与数值过渡动画。
///
/// 动画在"归一化位置空间"进行，而不是数值空间——这是关键：
/// 曲线纵轴按每帧数据的最大/最小值归一化，如果直接在数值空间插值，
/// 初始加载（全 0 → 随机值）时所有节点等比例放大，归一化会把公因子
/// 约掉，曲线第一帧就定格在最终形状，看起来"一闪而过"。
/// 改为对"节点在图中的相对位置"（0 = 底部 30% 线，1 = 顶部）插值后，
/// 每个节点在屏幕上做严格的匀速直线运动（等价 CSS 的 linear）。
///
class _TrendChartState extends State<TrendChart>
    with SingleTickerProviderStateMixin {
  /// 动画控制器：数据变化时从 0 跑到 1，驱动节点从旧位置滑到新位置。
  late final AnimationController _controller;

  /// 动画起点的归一化位置（上一帧画面上各节点所在高度）。
  List<double> _fromFractions = const [];

  /// 动画终点的归一化位置（当前 data 各节点应到达的高度）。
  List<double> _toFractions = const [];

  /// 当前选中节点下标；默认最后一个（今天）。
  int _selectedIndex = 0;

  /// 把一组数值换算成归一化位置：用这组数自身的最大/最小值归一化到 0..1。
  List<double> _fractionsFor(List<double> values) {
    if (values.isEmpty) return const [];
    var minV = values.first;
    var maxV = values.first;
    for (final v in values) {
      minV = math.min(minV, v);
      maxV = math.max(maxV, v);
    }
    // 全部相等（如空数据全 0）：位置统一取 0（贴底水平直线）。
    if (maxV == minV) return List.filled(values.length, 0.0);
    return [for (final v in values) (v - minV) / (maxV - minV)];
  }

  @override
  void initState() {
    super.initState();
    // vsync 参数让动画只在屏幕可见时刷新，避免后台空转耗电。
    _controller = AnimationController(vsync: this, duration: widget.duration);
    // 初始没有动画：起点 = 终点 = 传入数据的位置（如全 0 的空数据 → 底部直线）。
    _toFractions = _fractionsFor(widget.data.map((d) => d.value).toList());
    _fromFractions = List.of(_toFractions);
    // 默认选中最后一个节点。
    _selectedIndex = math.max(0, widget.data.length - 1);
  }

  @override
  void didUpdateWidget(covariant TrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newValues = widget.data.map((d) => d.value).toList();
    final newFractions = _fractionsFor(newValues);
    // 原始数值与标签都没变化时才视为普通父级重建。
    // 不能只比较归一化位置：例如 [0, 10] 与 [0, 100] 的位置形状相同，
    // 但数值刻度已经变化，仍需要让下面的状态完整接收这次数据更新。
    if (_sameData(oldWidget.data, widget.data)) return;

    if (newFractions.length != _toFractions.length) {
      // 节点数量变了，无法逐点插值，直接跳变到新位置。
      _fromFractions = List.of(newFractions);
    } else {
      // 以"当前画面上显示的位置"作为新动画的起点，切换中途也平滑衔接。
      _fromFractions = _displayFractions();
    }
    _toFractions = newFractions;
    // 数据更新（异步加载完成 / 切换时间档）后选中重置为最后一个节点。
    _selectedIndex = math.max(0, widget.data.length - 1);
    // 从 0 重新播放过渡动画。
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    // 释放动画资源，避免内存泄漏与 "AnimationController still active" 报错。
    _controller.dispose();
    super.dispose();
  }

  /// 逐项比较两组曲线原始数据是否完全一致。
  ///
  /// 标签或数值任一变化都属于一组新数据；只有全部相同才跳过动画与选中重置。
  bool _sameData(List<TrendDataPoint> a, List<TrendDataPoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].label != b[i].label || a[i].value != b[i].value) return false;
    }
    return true;
  }

  /// 计算当前画面各节点的归一化位置——匀速滑动模型。
  ///
  /// 控制器总时长对应"位移最大的节点"；每个节点分到的时长与其位移成正比
  /// （时长占比 = 自身位移 / 最大位移），因此所有节点以相同的像素速度
  /// 匀速移动（等价 CSS transition-timing-function: linear）：
  /// 位移小的节点提前到达终点并停住，位移最大的节点最后到达。
  List<double> _displayFractions() {
    final t = _controller.value; // 线性 0..1
    // 求全部节点中的最大位移。
    var maxDelta = 0.0;
    for (var i = 0; i < _toFractions.length; i++) {
      maxDelta = math.max(
        maxDelta,
        (_toFractions[i] - _fromFractions[i]).abs(),
      );
    }
    // 没有任何位移（数据没变）直接返回终点位置。
    if (maxDelta == 0) return _toFractions;

    return List<double>.generate(_toFractions.length, (i) {
      final from = _fromFractions[i];
      final to = _toFractions[i];
      final delta = (to - from).abs();
      // 位移为 0 的节点原地不动。
      if (delta == 0) return to;
      // 该节点的时长占比：位移越小越早走完。
      final share = delta / maxDelta;
      // 线性匀速推进，到达后停住。
      final progress = (t / share).clamp(0.0, 1.0);
      return from + (to - from) * progress;
    });
  }

  /// 处理节点点击：命中横向距离最近且在放大触控范围内的节点。
  ///
  /// 触控范围取 max(32, 节点间距的一半)，纵向不限制（整列高度都可点），
  /// 手指不需要精确点在小小的圆点上。
  void _handleTap(TapUpDetails details) {
    final size = context.size;
    if (size == null || widget.data.isEmpty) return;
    final w = size.width;
    final n = widget.data.length;
    // 与画笔使用完全相同的横坐标公式，保证点到哪就是画在哪。
    final x0 = widget.edgeInset;
    final x1 = w - widget.edgeInset;
    final step = n == 1 ? 0.0 : (x1 - x0) / (n - 1);

    // 找横向距离最近的节点。
    var best = 0;
    var bestDx = double.infinity;
    for (var i = 0; i < n; i++) {
      final dx = (details.localPosition.dx - (x0 + i * step)).abs();
      if (dx < bestDx) {
        bestDx = dx;
        best = i;
      }
    }

    // 放大的命中半径：至少 32 逻辑像素，或节点间距的一半。
    final threshold = math.max(32.0, n > 1 ? step / 2 : 32.0);
    if (bestDx <= threshold && best != _selectedIndex) {
      setState(() => _selectedIndex = best);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 主色缺省回退到品牌蓝；背景取卡片底色，用于选中节点的镂空圆心。
    final lineColor = widget.color ?? AppTokens.accent;
    final tokens = AppTokens.of(context);
    return SizedBox(
      // 固定高度，内部画布撑满此区域。
      height: widget.height,
      child: GestureDetector(
        // opaque 让整块矩形区域都参与点击命中，而不是只有画到像素的部分。
        behavior: HitTestBehavior.opaque,
        onTapUp: _handleTap,
        child: AnimatedBuilder(
          // 动画每前进一帧就重建一次画笔，画面随之滑动。
          animation: _controller,
          builder: (context, _) {
            // 用动画插值后的位置 + 最新数据的 label 组装"画面数据"。
            final fractions = _displayFractions();

            // 目标数据的取值范围：把位置反算成数值，保证选中节点
            // 上方的数字与节点高度始终一致（动画期间数字跟着位置走）。
            final targetValues = widget.data.map((d) => d.value).toList();
            var targetMin = 0.0;
            var targetMax = 0.0;
            if (targetValues.isNotEmpty) {
              targetMin = targetValues.reduce(math.min);
              targetMax = targetValues.reduce(math.max);
            }
            final span = targetMax - targetMin;

            final display = List<TrendDataPoint>.generate(
              widget.data.length,
              (i) => TrendDataPoint(
                label: widget.data[i].label,
                value: targetMin + fractions[i] * span,
              ),
            );
            return CustomPaint(
              painter: _TrendChartPainter(
                data: display,
                color: lineColor,
                bg: tokens.card,
                edgeInset: widget.edgeInset,
                selectedIndex: _selectedIndex,
                // 纵轴刻度固定按目标数据的范围计算：动画期间不随中间值
                // 重新归一化，节点位移才是严格的匀速直线（CSS linear）。
                minValue: targetMin,
                maxValue: targetMax,
              ),
            );
          },
        ),
      ),
    );
  }
}

///
/// 曲线画笔：底部分割线 + 渐变面积 + 平滑路径 + 节点 + 选中值 + 横轴标签。
///
/// 其中分割线、渐变面积、曲线三项从 x=0 画到 x=w（突破安全边界到屏幕边缘）；
/// 节点、选中值、label 全部限制在 [edgeInset, w-edgeInset] 的安全边界内。
///
class _TrendChartPainter extends CustomPainter {
  _TrendChartPainter({
    required this.data,
    required this.color,
    required this.bg,
    required this.edgeInset,
    required this.selectedIndex,
    required this.minValue,
    required this.maxValue,
  });

  /// 数据点列表（数值已是动画插值后的画面值）。
  final List<TrendDataPoint> data;

  /// 曲线主色。
  final Color color;

  /// 背景色（用于选中节点的镂空圆心）。
  final Color bg;

  /// 安全边界：节点与文字的横向排列范围。
  final double edgeInset;

  /// 当前选中节点下标。
  final int selectedIndex;

  /// 纵轴刻度下限（目标数据的最小值）。
  final double minValue;

  /// 纵轴刻度上限（目标数据的最大值）。
  final double maxValue;

  @override
  void paint(Canvas canvas, Size size) {
    // 没有数据就不画，避免后续取 reduce / 除零崩溃。
    if (data.isEmpty) return;

    final w = size.width;
    final h = size.height;

    // 底部预留 18px 给横轴日期文字；分割线画在这段预留区的顶部。
    final labelSpace = 18.0;
    final dividerY = h - labelSpace;
    // 顶部留白：给选中节点上方的数值文字腾位置。
    final topPadding = 30.0;

    // 纵轴刻度范围由外部按目标数据给定，动画期间保持固定：
    // 若按每帧中间值重新归一化，节点位移会被缩放抵消（初始加载时
    // 曲线瞬间定格）且速度不均匀。全部相等时人为 +1 拉开避免除 0。
    final minV = minValue;
    final maxV = maxValue == minValue ? minValue + 1 : maxValue;

    // 横坐标：节点排列在安全边界 [edgeInset, w-edgeInset] 内，首尾贴边界线。
    final n = data.length;
    final x0 = edgeInset;
    final x1 = w - edgeInset;
    final step = n == 1 ? 0.0 : (x1 - x0) / (n - 1);
    final xs = List<double>.generate(
      n,
      (i) => n == 1 ? (x0 + x1) / 2 : x0 + i * step,
    );

    // 纵坐标映射：把"归一化数值"换算成画布上的 y 坐标。
    // bottomFraction ∈ [0.3, 1.0]：最小值对应距分割线 30%（约三分之一），
    // 最大值对应顶部（bottom 100%）；最低点下方始终留出空间展示渐变色。
    double yFor(double v) {
      final normalized = (v - minV) / (maxV - minV); // 归一化到 0..1
      final bottomFraction = 0.3 + 0.7 * normalized;
      return topPadding + (1 - bottomFraction) * (dividerY - topPadding);
    }

    final ys = List<double>.generate(n, (i) => yFor(data[i].value));

    // 平滑曲线：从屏幕左边缘水平延展到首个节点，再用相邻两点的中点作为
    // 贝塞尔控制点生成柔和曲线穿过全部节点，最后水平延展到右边缘。
    final linePath = Path()
      ..moveTo(0, ys.first)
      ..lineTo(xs.first, ys.first);
    for (var i = 1; i < n; i++) {
      final prevX = xs[i - 1];
      final prevY = ys[i - 1];
      final curX = xs[i];
      final curY = ys[i];
      final midX = (prevX + curX) / 2;
      // 前半段水平过渡到中点，后半段从中点到当前点，形成 S 形平滑过渡。
      linePath.cubicTo(midX, prevY, midX, curY, curX, curY);
    }
    // 尾部延展到屏幕右边缘。
    linePath.lineTo(w, ys.last);

    // 面积路径：从曲线两端垂直落到分割线并闭合；因为曲线已延展到屏幕边缘，
    // 渐变面积同样铺满整行宽（突破安全边界）。
    final areaPath = Path.from(linePath)
      ..lineTo(w, dividerY)
      ..lineTo(0, dividerY)
      ..close();

    // 渐变填充：从曲线顶部（主色 25% 不透明）向下淡出到完全透明，
    // 一直铺到分割线，所以最低点下方也能看到渐变色。
    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, topPadding, w, dividerY - topPadding));
    canvas.drawPath(areaPath, areaPaint);

    // 底部分割线：从屏幕左边缘贯通到右边缘（突破安全边界）。
    final basePaint = Paint()
      ..color = const Color(0xFFEBEBEB)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, dividerY), Offset(w, dividerY), basePaint);

    // 曲线本身：主色描边，圆头圆角。
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);

    // 节点：普通节点小圆；选中节点大圆 + 中心镂空（露出背景色）以示区分。
    final dotPaint = Paint()..color = color;
    for (var i = 0; i < n; i++) {
      if (i == selectedIndex) {
        canvas.drawCircle(Offset(xs[i], ys[i]), 4.5, dotPaint);
        canvas.drawCircle(Offset(xs[i], ys[i]), 2, Paint()..color = bg);
      } else {
        canvas.drawCircle(Offset(xs[i], ys[i]), 3, dotPaint);
      }
    }

    // 选中节点上方的数值：动画期间跟着插值一起从旧值滚动到新值。
    final valueSpan = TextSpan(
      // 四舍五入取整显示。
      text: data[selectedIndex].value.round().toString(),
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
    );
    final valuePainter = TextPainter(
      text: valueSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    // 水平：以节点为中心；贴边节点做钳制，避免文字画出屏幕。
    final valueDx = (xs[selectedIndex] - valuePainter.width / 2).clamp(
      2.0,
      w - valuePainter.width - 2.0,
    );
    // 垂直：位于节点上方 6px；节点已在顶部时钳制到 0，防止裁切。
    final valueDy = (ys[selectedIndex] - valuePainter.height - 6).clamp(
      0.0,
      double.infinity,
    );
    valuePainter.paint(canvas, Offset(valueDx, valueDy));

    // 横轴标签：绘制全部节点的 label（7 个数据点就显示 7 个日期/文字）。
    // 首个在安全边界处左对齐、末个右对齐，避免贴边文字被裁切；中间居中。
    final labelStyle = TextStyle(fontSize: 10, color: const Color(0xFFA0A0A0));
    void drawLabel(String text, double x, TextAlign align) {
      final span = TextSpan(text: text, style: labelStyle);
      final painter = TextPainter(
        text: span,
        textDirection: TextDirection.ltr,
        textAlign: align,
      )..layout();
      // 根据对齐方式算出文字左边缘 x，使其整体居中/贴左/贴右。
      final dx = switch (align) {
        TextAlign.left => x,
        TextAlign.right => x - painter.width,
        _ => x - painter.width / 2,
      };
      // 标签画在分割线下方 4px 处（即底部预留区内）。
      painter.paint(canvas, Offset(dx, dividerY + 4));
    }

    for (var i = 0; i < n; i++) {
      final align = i == 0
          ? TextAlign.left
          : i == n - 1
          ? TextAlign.right
          : TextAlign.center;
      drawLabel(data[i].label, xs[i], align);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) {
    // 数据（动画每帧都是新列表）、颜色、边界、选中项或刻度变化时重绘。
    return oldDelegate.data != data ||
        oldDelegate.color != color ||
        oldDelegate.bg != bg ||
        oldDelegate.edgeInset != edgeInset ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.minValue != minValue ||
        oldDelegate.maxValue != maxValue;
  }
}
