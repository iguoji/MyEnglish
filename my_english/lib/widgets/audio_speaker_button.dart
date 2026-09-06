import 'dart:async';

import 'package:flutter/material.dart';

import '../common/theme.dart';

/// 应用内统一的听音按钮。
///
/// 视觉样式取自听音辨义模块：浅蓝色圆形底、Tabler 扬声器图标；播放时
/// 保留扬声器主体，并让两条声波弧线依次出现和隐藏。把它放到公共目录后，
/// 其他学习模块只需传入播放状态和点击回调，就能保持按钮外观与交互一致。
class AudioSpeakerButton extends StatefulWidget {
  /// 创建统一听音按钮。
  const AudioSpeakerButton({
    required this.isPlaying,
    required this.onTap,
    this.size = AppSize.speakerButton,
    this.iconSize = AppIcon.i20,
    super.key,
  });

  /// 当前是否正在播放发音。
  final bool isPlaying;

  /// 点击按钮时执行的播放逻辑。
  final VoidCallback onTap;

  /// 圆形按钮的边长。
  final double size;

  /// Tabler 扬声器图标的尺寸。
  final double iconSize;

  @override
  State<AudioSpeakerButton> createState() => _AudioSpeakerButtonState();
}

/// 统一听音按钮的播放反馈动画。
///
/// 动画放在公共组件内部，而不是由每个页面各自实现，确保听音辨义、
/// 拼写巩固以及以后新增的听音入口都使用同样的弧线和波纹效果。
class _AudioSpeakerButtonState extends State<AudioSpeakerButton> {
  /// 播放动画的当前相位。
  ///
  /// 听音按钮只需要表达“正在播放”，不需要逐帧刷新。用低频相位更新
  /// 仍能保留弧线和波纹效果，同时避免模拟器持续高负载重绘。
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  /// 仅在播放时运行的低频动画定时器。
  Timer? _timer;

  /// 仅在播放时运行的弧线切换定时器。
  ///
  /// 弧线不需要跟随每一帧变化，单独每 250 毫秒切换一次即可准确表达
  /// “隐藏 → 显示 → 隐藏”的节奏，也能避免为了等间隔计时而提高刷新率。
  Timer? _arcTimer;

  /// 播放时是否显示远处的长弧线。
  final ValueNotifier<bool> _outerArcVisible = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) _startTimer();
  }

  @override
  void didUpdateWidget(covariant AudioSpeakerButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying == oldWidget.isPlaying) return;
    if (widget.isPlaying) {
      _startTimer();
    } else {
      _stopTimer();
    }
  }

  /// 播放时以约 10 帧/秒推进动画相位。
  ///
  /// 这里刻意不使用 AnimationController：这个按钮会出现在多个页面，
  /// 用低频定时器只刷新一个小型 ValueNotifier，能保留动画又避免模拟器
  /// 持续进行高频整页重绘。
  void _startTimer() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(milliseconds: AppDuration.ms100), (
      _,
    ) {
      if (!mounted || !widget.isPlaying) return;
      // 每 100 毫秒推进 0.1，仅用于驱动圆形波纹；弧线由独立的 250 毫秒
      // 定时器控制，避免声纹刷新频率影响弧线节奏。
      _progress.value = (_progress.value + 0.1) % 1;
    });
    _startArcTimer();
  }

  /// 开始播放时先隐藏长弧线，随后每 250 毫秒切换一次长弧线状态。
  void _startArcTimer() {
    if (_arcTimer != null) return;
    _outerArcVisible.value = false;
    _arcTimer = Timer.periodic(
      const Duration(milliseconds: AppDuration.ms250),
      (_) {
        if (!mounted || !widget.isPlaying) return;
        _outerArcVisible.value = !_outerArcVisible.value;
      },
    );
  }

  /// 停止动画并恢复静止画面。
  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _arcTimer?.cancel();
    _arcTimer = null;
    _progress.value = 0;
    _outerArcVisible.value = false;
  }

  @override
  void dispose() {
    _stopTimer();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _progress,
      builder: (context, progress, _) => ValueListenableBuilder<bool>(
        valueListenable: _outerArcVisible,
        builder: (context, outerArcVisible, _) => SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // 两圈波纹错峰向外扩散，播放时用户即使不看文字也能感知状态。
              if (widget.isPlaying)
                for (var ring = 0; ring < 2; ring += 1)
                  Positioned.fill(
                    child: Transform.scale(
                      scale: 1 + _ringProgress(progress, ring) * 0.85,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppTokens.primary.withValues(
                            alpha:
                                (1 - _ringProgress(progress, ring)) *
                                AppAlpha.a22,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
              Material(
                // 空闲时保留听音辨义的浅蓝底；播放时加深为品牌蓝，
                // 让波纹中心和弧线形成清楚的视觉焦点。
                color: widget.isPlaying
                    ? AppTokens.primary
                    : AppTokens.primary.withValues(alpha: AppAlpha.a12),
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: BorderRadius.circular(AppRadius.roundedPill),
                  child: SizedBox(
                    width: widget.size,
                    height: widget.size,
                    child: Center(child: _buildSpeakerIcon(outerArcVisible)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 播放时固定显示短弧，只让长弧每 250 毫秒隐藏/显示一次。
  ///
  /// 不能把 Tabler 的 volume、volume2、volume3 叠加使用：这些字体图标
  /// 自身已经包含不同数量的弧线，叠加后会让弧线看起来一直存在。播放态
  /// 改用同一枚 Tabler volume 的路径绘制扬声器主体，再单独绘制两条原始
  /// 弧线路径，这样播放态就能只控制第二条弧线的显示和隐藏。
  Widget _buildSpeakerIcon(bool outerArcVisible) {
    if (!widget.isPlaying) {
      return Icon(
        AppGlyph.speaker,
        size: widget.iconSize,
        color: AppTokens.primary,
      );
    }
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.iconSize),
        painter: _PlayingSpeakerPainter(
          color: Colors.white,
          // 播放态第一条短弧始终显示，只有第二条长弧参与节奏切换。
          innerArcVisible: true,
          outerArcVisible: outerArcVisible,
        ),
      ),
    );
  }

  /// 计算每一圈波纹的错峰进度。
  double _ringProgress(double progress, int ring) =>
      (progress + ring * 0.5) % 1;
}

/// 播放态扬声器的 Tabler 路径绘制器。
///
/// Tabler 字体图标是把整枚 SVG 压缩进一个字形里，无法只让其中一条弧线
/// 隐藏。因此这里保留听音拼写原型中的 Tabler `volume` 几何路径，只把主体、
/// 内弧、外弧拆成三条可独立绘制的路径；这不是另造图标，而是把同一枚图标
/// 拆成可动画的组成部分。
class _PlayingSpeakerPainter extends CustomPainter {
  /// 创建播放态扬声器绘制器。
  const _PlayingSpeakerPainter({
    required this.color,
    required this.innerArcVisible,
    required this.outerArcVisible,
  });

  /// 图标颜色。
  final Color color;

  /// 是否显示近处的短弧线。
  final bool innerArcVisible;

  /// 是否显示远处的长弧线。
  final bool outerArcVisible;

  @override
  void paint(Canvas canvas, Size size) {
    // Tabler 图标的标准 viewBox 是 24×24；按传入字号等比缩放并居中。
    final scale = size.shortestSide / 24;
    final offsetX = (size.width - 24 * scale) / 2;
    final offsetY = (size.height - 24 * scale) / 2;
    canvas
      ..save()
      ..translate(offsetX, offsetY)
      ..scale(scale);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 扬声器主体始终保持不透明；播放动画只改变两条弧线，避免主体也闪烁。
    canvas.drawPath(_speakerBodyPath(), stroke);

    if (innerArcVisible) {
      canvas.drawPath(_innerArcPath(), stroke);
    }
    if (outerArcVisible) {
      canvas.drawPath(_outerArcPath(), stroke);
    }
    canvas.restore();
  }

  /// Tabler volume 的扬声器主体。
  Path _speakerBodyPath() => Path()
    ..moveTo(6, 15)
    ..lineTo(4, 15)
    ..cubicTo(3.45, 15, 3, 14.55, 3, 14)
    ..lineTo(3, 10)
    ..cubicTo(3, 9.45, 3.45, 9, 4, 9)
    ..lineTo(6, 9)
    ..lineTo(9.5, 4.5)
    ..cubicTo(10.1, 3.7, 11, 4.2, 11, 5)
    ..lineTo(11, 19)
    ..cubicTo(11, 19.8, 10.1, 20.3, 9.5, 19.5)
    ..close();

  /// 原型中的近处弧线：`M15 8a5 5 0 0 1 0 8`。
  ///
  /// 下面这个 `Radius.circular(5)` 不是「圆角」，而是这段圆弧本身的半径——
  /// 它决定这道声波弯多大的弧，跟卡片四角的圆角是两码事，所以既不参与
  /// 圆角台阶的收敛，也不该被「不许出现裸数字」的检查拦下来。
  /// 5 和下面的 9 都是从原型的 SVG 路径里原样抄来的，改一个数弧线就走形了。
  Path _innerArcPath() => Path()
    ..moveTo(15, 8)
    ..arcToPoint(
      const Offset(15, 16),
      radius: const Radius.circular(5),
      clockwise: true,
    );

  /// 原型中的远处弧线：`M17.7 5a9 9 0 0 1 0 14`。
  ///
  /// 同上：`Radius.circular(9)` 是圆弧半径，不是圆角半径。
  Path _outerArcPath() => Path()
    ..moveTo(17.7, 5)
    ..arcToPoint(
      const Offset(17.7, 19),
      radius: const Radius.circular(9),
      clockwise: true,
    );

  @override
  bool shouldRepaint(covariant _PlayingSpeakerPainter oldDelegate) {
    return color != oldDelegate.color ||
        innerArcVisible != oldDelegate.innerArcVisible ||
        outerArcVisible != oldDelegate.outerArcVisible;
  }
}
