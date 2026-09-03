// 本文件是 development_page.dart 的一部分（part of），与主文件共享同一个
// library，因此可以直接使用页面内部的私有类型（下划线开头的类），不需要
// 单独 import 任何依赖。这里集中放置动画与错误反馈组件，让主文件只保留页面骨架与状态逻辑。
part of '../development_page.dart';

/// 题目气泡里的扬声器图标。
///
/// 不播放时两条声波弧线常半透明常驻，提示“点我可以重听”；播放时两条弧线
/// 依次亮起、再依次熄灭，像水波一圈圈从喇叭口荡出去，对应 HTML 原型的
/// `.sound-wave` 动画（弧线错开 0.14s，形成“依次”的扩散感）。
class _SoundWaveIcon extends StatefulWidget {
  /// 创建扬声器图标。
  const _SoundWaveIcon({required this.playing, required this.size, super.key});

  /// 是否正在播放。
  final bool playing;

  /// 图标边长（正方形）。
  final double size;

  @override
  State<_SoundWaveIcon> createState() => _SoundWaveIconState();
}

/// 驱动两条弧线循环的动画。
class _SoundWaveIconState extends State<_SoundWaveIcon>
    with SingleTickerProviderStateMixin {
  /// 循环动画控制器，周期与原型 soundWave 动画一致（960ms）。
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 960),
    );
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _SoundWaveIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) return;
    if (widget.playing) {
      // 每次重新播放从第一帧开始，避免声音已经结束但图标仍持续占用 CPU。
      _controller
        ..value = 0
        ..repeat();
    } else {
      // 未播放时弧线是静态半透明提示，不需要持续重绘 CustomPaint。
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = AppTokens.accent;
    // 原型未播放时不挂 animation，弧线以 currentColor 的完整不透明度静止；
    // 播放时才切到 0.22 → 1 → 0.22 的声波包络。
    final idle = 1.0;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          // 第二条弧线比第一条晚 0.146 个周期亮起，形成“依次扩散”。
          final level0 = widget.playing ? _wave(t) : idle;
          final level1 = widget.playing ? _wave((t - 0.146) % 1) : idle;
          return CustomPaint(
            painter: _SoundWavePainter(color, level0, level1),
            size: Size(widget.size, widget.size),
          );
        },
      ),
    );
  }

  /// 复刻 HTML 的 @keyframes soundWave：暗(0.22)→亮(1)→暗 的循环包络。
  static double _wave(double t) {
    t = t - t.floorToDouble();
    if (t < 0.14) return 0.22;
    if (t < 0.30) return _lerp(0.22, 1.0, (t - 0.14) / 0.16);
    if (t < 0.52) return 1.0;
    if (t < 0.68) return _lerp(1.0, 0.22, (t - 0.52) / 0.16);
    return 0.22;
  }

  /// 线性插值，并夹在 [0,1]。
  static double _lerp(double a, double b, double x) =>
      a + (b - a) * x.clamp(0.0, 1.0);
}

/// 把扬声器本体 + 两条声波弧线画进一个 24×24 坐标系（与原型 SVG 完全一致）。
class _SoundWavePainter extends CustomPainter {
  /// 创建声波画笔。
  const _SoundWavePainter(this.color, this.level0, this.level1);

  /// 主色（喇叭本体与弧线同色）。
  final Color color;

  /// 第一条弧线亮度（0.22~1），同时决定透明度与缩放。
  final double level0;

  /// 第二条弧线亮度。
  final double level1;

  @override
  void paint(Canvas canvas, Size size) {
    // 把画布缩放到 24×24 坐标系，便于直接复用 HTML 的 SVG 路径坐标。
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);

    // 喇叭本体：M4 9v6h4l4 3V6L8 9H4Z。
    final bodyPaint = Paint()..color = color;
    canvas.drawPath(
      Path()
        ..moveTo(4, 9)
        ..lineTo(4, 15)
        ..lineTo(8, 15)
        ..lineTo(12, 18)
        ..lineTo(12, 6)
        ..lineTo(8, 9)
        ..close(),
      bodyPaint,
    );

    // 内侧小弧线：M15 9.2 c1.7 1.55 1.7 4.05 0 5.6。
    _drawArc(
      canvas,
      Path()
        ..moveTo(15, 9.2)
        ..cubicTo(16.7, 10.75, 16.7, 13.25, 15, 14.8),
      level0,
    );
    // 外侧大弧线：M18 6.7 c3.1 2.93 3.1 7.67 0 10.6。
    _drawArc(
      canvas,
      Path()
        ..moveTo(18, 6.7)
        ..cubicTo(21.1, 9.63, 21.1, 14.37, 18, 17.3),
      level1,
    );

    canvas.restore();
  }

  /// 以喇叭口 (10,12) 为缩放原点绘制一条声波弧线，亮度越高越亮、越大。
  void _drawArc(Canvas canvas, Path path, double level) {
    final opacity = level.clamp(0.0, 1.0);
    final scale = 0.9 + 0.1 * ((level - 0.22) / 0.78).clamp(0.0, 1.0);
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.translate(10, 12);
    canvas.scale(scale, scale);
    canvas.translate(-10, -12);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SoundWavePainter old) =>
      old.level0 != level0 || old.level1 != level1 || old.color != color;
}

/// 把 HTML 原型 `@keyframes dot` 的半程高亮曲线转换成 0~1 的进度值。
///
/// 原型在 0%/100% 保持原尺寸和浅色，在 50% 放大到 1.25 倍并切换主色；
/// 两段都使用 ease-in-out。加载、语音和槽位只传入不同的相位，不再各自
/// 复制一套容易产生偏差的正弦公式。
abstract final class _DotAnimation {
  /// 根据一个 0~1 的周期相位，返回当前高亮进度（0~1）。
  static double pulse(double phase) {
    final normalized = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    return Curves.easeInOut.transform(normalized.clamp(0.0, 1.0).toDouble());
  }

  /// 根据动画已经运行的总周期和本点延迟，计算当前高亮进度。
  ///
  /// [AnimationController.value] 每轮会回到 0，直接拿它减延迟会在每一轮
  /// 开头产生闪回。`lastElapsedDuration` 保留了 repeat 的累计时间，因此既
  /// 能复刻 CSS 首轮延迟，又能保证后续轮次无缝衔接。
  static double delayedPulse({
    required Duration? elapsed,
    required Duration period,
    required double delayCycles,
  }) {
    final elapsedCycles =
        (elapsed ?? Duration.zero).inMicroseconds / period.inMicroseconds;
    final raw = elapsedCycles - delayCycles;
    if (raw <= 0) return 0;
    return pulse(raw - raw.floorToDouble());
  }
}

/// 一排可复用的圆点动画（加载气泡、语音消息和题目槽位共用）。
///
/// HTML 原型里加载态和语音态都直接使用 `.voice-dots > i`，只有圆点数量
/// 和是否开启动画不同。这里也只保留一套渲染逻辑：每个点以 75ms 错开，
/// 从 `--dot` 平滑过渡到消息主色并放大到 1.25 倍，避免语音消息另用一套
/// 粗略的同步缩放动画。
class _AnimatedDots extends StatefulWidget {
  /// 创建圆点组。
  const _AnimatedDots({required this.playing, this.count = 6});

  /// 是否播放动画；加载态传 true，语音消息未播放时传 false。
  final bool playing;

  /// 圆点数量：加载态为 3，语音题/语音消息为 6。
  final int count;

  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

/// 管理整排圆点的循环动画；同一个控制器保证圆点之间只有相位差，没有
/// 多个独立计时器造成的漂移。
class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  /// 循环动画控制器，周期与原型 dot 动画一致（720ms）。
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: DevelopmentLayout.dotAnimationDuration,
    );
    if (widget.playing) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _AnimatedDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing == oldWidget.playing) return;
    if (widget.playing) {
      // 每次开始播放都从第一个圆点起步，第一帧不会随机落在动画中段。
      _controller
        ..value = 0
        ..repeat();
    } else {
      // 停止时回到原型的静止浅蓝点，并暂停 Ticker 节省页面资源。
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width =
        widget.count * DevelopmentLayout.slotDotSize +
        (widget.count - 1) * DevelopmentLayout.slotGap;
    return RepaintBoundary(
      // 只让这块圆点画布在播放时重绘，聊天列表中的其它历史消息不跟着
      // 每帧重新布局，降低播放动画对 CPU 的压力。
      child: CustomPaint(
        size: Size(width, DevelopmentLayout.slotDotSize),
        painter: _VoiceDotsPainter(
          count: widget.count,
          animation: _controller,
          playing: widget.playing,
        ),
      ),
    );
  }
}

/// 在一个 CustomPaint 中绘制整排语音/加载圆点。
///
/// 原先每个圆点都包含一个 AnimatedBuilder、Transform 和 BoxDecoration；
/// 播放时它们会分别创建布局对象。改为单画布后，仍保留原型的错峰节奏，
/// 但每帧只进行一次布局和一次画布刷新。
class _VoiceDotsPainter extends CustomPainter {
  const _VoiceDotsPainter({
    required this.count,
    required this.animation,
    required this.playing,
  }) : super(repaint: animation);

  final int count;
  final AnimationController animation;
  final bool playing;

  @override
  void paint(Canvas canvas, Size size) {
    final elapsed = animation.lastElapsedDuration;
    final period = DevelopmentLayout.dotAnimationDuration;
    final elapsedCycles =
        (elapsed ?? Duration.zero).inMicroseconds / period.inMicroseconds;
    final radius = DevelopmentLayout.slotDotSize / 2;
    for (var index = 0; index < count; index += 1) {
      final delayCycles =
          DevelopmentLayout.dotAnimationDelayMs / period.inMilliseconds * index;
      final raw = elapsedCycles - delayCycles;
      final pulse = playing && raw > 0
          ? _DotAnimation.pulse(raw - raw.floorToDouble())
          : 0.0;
      final center = Offset(
        radius +
            index * (DevelopmentLayout.slotDotSize + DevelopmentLayout.slotGap),
        size.height / 2,
      );
      final paint = Paint()
        ..color = Color.lerp(
          DevelopmentLayout.typingDot,
          AppTokens.accent,
          pulse,
        )!
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        center,
        radius * (1 + (DevelopmentLayout.dotAnimationPeakScale - 1) * pulse),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceDotsPainter oldDelegate) =>
      oldDelegate.count != count ||
      oldDelegate.playing != playing ||
      oldDelegate.animation != animation;
}

/// 单个字母槽的空位小圆点：播放音频时轻微呼吸（对应原型 quiz-bubble.playing
/// 下 .slot.dot:after 的 dot 动画），不播放时静止。
///
/// 槽位使用题目气泡传入的共享时间轴，不为每个字母再创建一个 Ticker。
class _BreathingDot extends StatelessWidget {
  /// 创建空位小圆点。
  const _BreathingDot({
    required this.playing,
    required this.animation,
    this.phaseOffset = 0,
  });

  /// 是否正在播放，决定圆点是否呼吸。
  final bool playing;

  /// 题目气泡内所有槽位共用的呼吸时间轴。
  final Animation<double>? animation;

  /// 本圆点在整排槽位中的相位错开量（0~1，一个完整周期为 1）。
  ///
  /// 对应 HTML 原型 `.quiz-bubble.playing .slot.dot:after` 的
  /// `animation-delay: calc(var(--i)*60ms)`：每个槽位比前一个晚 60ms 亮起，
  /// 让一排空位圆点从前往后依次呼吸，而不是所有圆点同时起落。
  final double phaseOffset;

  @override
  Widget build(BuildContext context) {
    final animation = this.animation;
    if (!playing || animation == null) return _buildDot(0);
    return CustomPaint(
      size: const Size(
        DevelopmentLayout.slotDotSize,
        DevelopmentLayout.slotDotSize,
      ),
      painter: _SlotDotPainter(animation: animation, phaseOffset: phaseOffset),
    );
  }

  /// 根据高亮进度绘制固定尺寸的圆点。
  Widget _buildDot(double pulse) {
    return Transform.scale(
      scale: 1 + (DevelopmentLayout.dotAnimationPeakScale - 1) * pulse,
      child: Container(
        width: DevelopmentLayout.slotDotSize,
        height: DevelopmentLayout.slotDotSize,
        decoration: BoxDecoration(
          color: Color.lerp(
            DevelopmentLayout.typingDot,
            AppTokens.accent,
            pulse,
          ),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// 绘制单个拼写槽位圆点，直接监听整排共享动画控制器。
class _SlotDotPainter extends CustomPainter {
  const _SlotDotPainter({required this.animation, required this.phaseOffset})
    : super(repaint: animation);

  final Animation<double> animation;
  final double phaseOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final controller = animation is AnimationController
        ? animation as AnimationController
        : null;
    final pulse = controller == null
        ? 0.0
        : _DotAnimation.delayedPulse(
            elapsed: controller.lastElapsedDuration,
            period: DevelopmentLayout.dotAnimationDuration,
            delayCycles: phaseOffset,
          );
    final paint = Paint()
      ..color = Color.lerp(
        DevelopmentLayout.typingDot,
        AppTokens.accent,
        pulse,
      )!;
    canvas.drawCircle(
      size.center(Offset.zero),
      DevelopmentLayout.slotDotSize /
          2 *
          (1 + (DevelopmentLayout.dotAnimationPeakScale - 1) * pulse),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SlotDotPainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.phaseOffset != phaseOffset;
}

/// 连续“用户错误”消息的折叠组：折叠态只显示最新一条错误气泡，左上角红牌标 N，
/// 气泡后露一条浅红叠层阴影暗示底下还有更多；点击整组可展开看全部，底部有
/// “展开 N 条 / 收起”脚注。对应 HTML 原型的 `.err-stack` 思路。
class _ErrorStack extends StatefulWidget {
  /// 创建错误折叠组。
  const _ErrorStack({required this.messages, required this.tokens});

  /// 连续的错误用户消息（已按出现顺序收集）。
  final List<_DevelopmentMessage> messages;

  /// 当前主题色令牌。
  final AppTokens tokens;

  @override
  State<_ErrorStack> createState() => _ErrorStackState();
}

/// 管理折叠组的展开/收起状态。
class _ErrorStackState extends State<_ErrorStack> {
  /// 是否展开显示全部错误。
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final tokens = widget.tokens;
    final errors = widget.messages;
    final latest = errors.last;
    final count = errors.length;
    final availableWidth =
        MediaQuery.sizeOf(context).width - DevelopmentLayout.chatInset * 2;
    final maxBubbleWidth = availableWidth * .82;

    final body = _open
        ? _buildExpanded(errors, count, maxBubbleWidth, tokens)
        : _buildCollapsed(latest, count, maxBubbleWidth, tokens);
    return Align(alignment: Alignment.centerRight, child: body);
  }

  /// 折叠态：只保留最新错误气泡，左侧显示「数量 + ×」，后面露出浅红叠层。
  Widget _buildCollapsed(
    _DevelopmentMessage latest,
    int count,
    double maxBubbleWidth,
    AppTokens tokens,
  ) {
    final bubble = IntrinsicWidth(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Stack 的宽度由真实气泡决定，浅红叠层再左右各缩一点；
            // 这样不会因为父级拿到聊天区最大宽度而向左拉长。
            Positioned(
              right: DevelopmentLayout.errStackShadowInset,
              top: DevelopmentLayout.errStackShadowTop,
              bottom: 5,
              left: 3,
              child: Container(
                decoration: BoxDecoration(
                  color: DevelopmentLayout.redStackShadow,
                  borderRadius: BorderRadius.circular(
                    DevelopmentLayout.bubbleRadius,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _UserBubble(
                text: latest.text ?? '',
                danger: true,
                checked: false,
                tokens: tokens,
              ),
            ),
          ],
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = true),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          bubble,
          // 数量牌脱离布局流，正好浮在气泡左侧；这样错误组宽度仍由
          // 气泡自身决定，和原型 `.err-badge { right: 100% }` 一致。
          Positioned(
            left: -41,
            top: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.center,
              child: _ErrorCountBadge(count: count, showClose: true),
            ),
          ),
        ],
      ),
    );
  }

  /// 展开态：左侧凹槽放自适应大括号和数量牌，右侧竖排所有错误气泡。
  Widget _buildExpanded(
    List<_DevelopmentMessage> errors,
    int count,
    double maxBubbleWidth,
    AppTokens tokens,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = false),
      child: ConstrainedBox(
        // 原型展开态在气泡列左侧额外留 38px 凹槽，因此整体宽度是
        //「气泡最大宽度 + 凹槽/内边距」，但仍不能超过聊天可用宽度。
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        child: Padding(
          // 左侧 38px 专门容纳数量牌和大括号；右侧不能再留空，否则
          // 展开后的每条气泡都会比折叠态向左偏移，右边缘无法对齐。
          padding: const EdgeInsets.fromLTRB(38, 8, 0, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  // 气泡列是 Stack 的唯一非定位子项，宽度按内容自适应，
                  // 最宽不超过原型消息的 82%。
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (
                        var index = 0;
                        index < errors.length;
                        index += 1
                      ) ...[
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                          child: _UserBubble(
                            text: errors[index].text ?? '',
                            danger: true,
                            checked: false,
                            tokens: tokens,
                          ),
                        ),
                        if (index != errors.length - 1)
                          const SizedBox(height: 6),
                      ],
                    ],
                  ),
                  // Padding 左侧的坐标原点是气泡列起点；原型括号位于整体左侧
                  // 18px，因此这里向左回退 20px（38 - 18）。
                  Positioned(
                    left: -20,
                    top: 0,
                    bottom: 0,
                    width: 18,
                    child: CustomPaint(
                      painter: _ErrorBracePainter(
                        color: DevelopmentLayout.red.withValues(alpha: .65),
                      ),
                    ),
                  ),
                  // 数量牌位于整体左侧 -2px，所以相对气泡列回退 40px。
                  Positioned(
                    left: -40,
                    top: 0,
                    bottom: 0,
                    child: Align(
                      alignment: Alignment.center,
                      child: _ErrorCountBadge(count: count),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              _ErrorStackFoot(
                onOpenChanged: () => setState(() => _open = false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 错误组左侧的数量牌；折叠时追加一个中性的 Tabler × 图标，展开时只显示数字。
class _ErrorCountBadge extends StatelessWidget {
  const _ErrorCountBadge({required this.count, this.showClose = false});

  final int count;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: DevelopmentLayout.errBadgeSize,
          height: DevelopmentLayout.errBadgeSize,
          decoration: const BoxDecoration(
            color: DevelopmentLayout.red,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
        if (showClose) ...[
          const SizedBox(width: 6),
          Icon(TablerIcons.x, size: 11, color: Color(0xFF8A98AB)),
        ],
      ],
    );
  }
}

/// 展开态右下角脚注，使用 Tabler 箭头图标代替文字型箭头。
class _ErrorStackFoot extends StatelessWidget {
  const _ErrorStackFoot({required this.onOpenChanged});

  final VoidCallback onOpenChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpenChanged,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '收起',
            style: TextStyle(
              color: DevelopmentLayout.red,
              fontSize: DevelopmentLayout.errFootTextSize,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 3),
          const Icon(
            TablerIcons.chevronUp,
            size: 13,
            color: DevelopmentLayout.red,
          ),
        ],
      ),
    );
  }
}

/// 展开态错误列表左侧的大括号装饰，沿用原型的 18×100 路径比例。
class _ErrorBracePainter extends CustomPainter {
  const _ErrorBracePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // 原型 JS 会把括号上下端钉在第一条/最后一条气泡的中心，而不是
    // 贴着列表外框。默认气泡高度为 46px，所以中心距上下各约 23px。
    final top = size.height > 46 ? 23.0 : size.height / 2;
    final bottom = size.height > 46 ? size.height - 23.0 : size.height / 2;
    final mid = (top + bottom) / 2;
    final path = Path()
      ..moveTo(size.width - 2, top)
      ..cubicTo(
        size.width * .62,
        top,
        size.width * .38,
        top + 7,
        size.width * .38,
        top + 18,
      )
      ..lineTo(size.width * .38, mid - 8)
      ..lineTo(2, mid)
      ..lineTo(size.width * .38, mid + 8)
      ..lineTo(size.width * .38, bottom - 18)
      ..cubicTo(
        size.width * .38,
        bottom - 7,
        size.width * .62,
        bottom,
        size.width - 2,
        bottom,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ErrorBracePainter oldDelegate) =>
      oldDelegate.color != color;
}
