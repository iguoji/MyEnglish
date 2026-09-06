// dart:async 提供 Timer，用来低频驱动光标的亮灭切换。
import 'dart:async';

// material.dart 提供 StatefulWidget、SizedBox 等基础绘制能力。
import 'package:flutter/material.dart';

// 引入设计令牌，光标默认使用品牌主色。
import '../common/theme.dart';

///
/// 全App统一的「输入光标」：一根竖着的小蓝线，在亮和灭之间来回硬切换。
///
/// 生活化解释：就是你在手机输入框里看到的那根一闪一闪的竖线。
///
/// 两处用到它，观感必须完全一样：
///
/// 1. 拼写巩固的字母格——提示「下一个字母敲在这里」；
/// 2. 词性含义面板的揭示模式（`lib/widgets/pos_meaning_panel.dart`）
///    ——提示「下一条含义填在这里」。
///
/// 实现上刻意不用 `AnimationController`：那会按屏幕刷新率每秒重绘 60 次，
/// 而光标只需要每半秒切换一次。这里用「一次性 Timer 递归排下一次」的写法，
/// 既能准确复刻 CSS `steps(1, end)` 的硬切效果（不是渐隐渐现），
/// 也能做到亮 472 毫秒、灭 578 毫秒这种不对称节奏，同时几乎不占 CPU。
///
/// 这两个数不收进 `AppDuration` 的台阶：它们是一对配比（一个周期的 45% / 55%），
/// 并成同一个台阶值就会变成对称闪烁，和原型的节奏对不上。
///
/// 应用退到后台时会主动停表，回到前台再从「亮」开始，避免白白唤醒定时器。
///
class BlinkingCaret extends StatefulWidget {
  ///
  /// 创建一个闪烁光标。
  const BlinkingCaret({
    required this.height,
    this.width = defaultWidth,
    this.color,
    super.key,
  });

  ///
  /// 光标默认粗细，直接取设计令牌总表的造型档。
  ///
  /// 两处调用方（字母格、词性及含义面板）都要按这个值算居中偏移，所以粗细
  /// 只能有一个出处。收敛前是三处各写一遍 2，还靠注释互相提醒「改动请同步」。
  static const double defaultWidth = AppSize.caretWidth;

  ///
  /// 一个完整闪烁周期的毫秒数。
  ///
  /// 亮灭时长不写死两个数，而是从这一个周期按比例算出来：原型的关键帧是
  /// 「0%–45% 显示、55%–100% 隐藏」，把 45% 这个比例直接写进代码，
  /// 以后想让光标快一点只改这一个数，亮灭的不对称节奏会自动跟着保持。
  static const int cycleMs = 1050;

  ///
  /// 一个闪烁周期里「亮」的毫秒数（周期的 45%，等于 472）。
  static const int visibleMs = cycleMs * 45 ~/ 100;

  ///
  /// 一个闪烁周期里「灭」的毫秒数（周期剩下的 55%，等于 578）。
  static const int hiddenMs = cycleMs - visibleMs;

  ///
  /// 光标高度；由调用方决定，因为字母格和含义行的可用高度不一样。
  final double height;

  ///
  /// 光标粗细。
  final double width;

  ///
  /// 光标颜色；不传时使用品牌主色。
  final Color? color;

  @override
  State<BlinkingCaret> createState() => _BlinkingCaretState();
}

///
/// 光标状态：只维护「现在该亮还是该灭」和那一个定时器。
///
class _BlinkingCaretState extends State<BlinkingCaret>
    with WidgetsBindingObserver {
  ///
  /// 下一次亮灭切换的定时器；同一时刻最多只有一个。
  Timer? _blinkTimer;

  ///
  /// 当前是否处于「亮」的半个周期。
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    // 订阅前后台变化，页面被切走时好停表。
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  ///
  /// 启动闪烁；重复调用不会叠出第二个定时器。
  void _start() {
    if (_blinkTimer != null) return;
    // 每次开始都先亮，用户一眼就能看到光标落在哪。
    _visible = true;
    _scheduleNext(const Duration(milliseconds: BlinkingCaret.visibleMs));
  }

  ///
  /// 排下一次切换；用一次性 Timer 才能表达亮灭时长不相等的节奏。
  void _scheduleNext(Duration delay) {
    _blinkTimer = Timer(delay, () {
      _blinkTimer = null;
      if (!mounted) return;
      setState(() => _visible = !_visible);
      _scheduleNext(
        Duration(
          milliseconds: _visible
              ? BlinkingCaret.visibleMs
              : BlinkingCaret.hiddenMs,
        ),
      );
    });
  }

  ///
  /// 停表并恢复成「亮」，避免下次回到页面时光标停在看不见的那一半。
  void _stop() {
    _blinkTimer?.cancel();
    _blinkTimer = null;
    _visible = true;
  }

  ///
  /// 应用回到前台恢复闪烁，退到后台立刻停表。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 外框尺寸恒定，只切换里面画不画，这样闪烁不会让周围内容跟着抖。
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: _visible
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: widget.color ?? AppTokens.primary,
                // 999 等于「两头做成半圆」，和拼写巩固的下划线圆头一致。
                borderRadius: BorderRadius.circular(AppRadius.roundedPill),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
